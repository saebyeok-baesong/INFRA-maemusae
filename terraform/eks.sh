#!/usr/bin/env bash
# cluster 층을 코어타임에만 띄우는 도우미. 사용법은 README.md
# 수동 실행과 GitHub Actions 스케줄(.github/workflows/eks.yml)이 같은 함수를 부른다.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="$DIR/cluster"
NAME="${NAME:-maemusae}"
REGION="${AWS_REGION:-ap-northeast-2}"

# 코어타임(KST). UP_AT 은 eks.yml 의 올리기 cron 과 같은 시각이어야 한다
UP_AT="${UP_AT:-09:30}"
CORE_END="${CORE_END:-18:00}"
HOLD_MAX="${HOLD_MAX:-22:00}"

usage() {
  cat >&2 <<'USAGE'
usage:
  eks.sh up                 cluster 층 apply, 노드 Ready 까지 기다린다
  eks.sh down               Argo CD 앱 삭제 -> LoadBalancer, PVC 정리 -> cluster 층 destroy -> leftovers
  eks.sh drain              KUBECONFIG 클러스터에서 down 의 클러스터 안 정리만 한다
  eks.sh leftovers          cluster 층 리소스가 남았는지 확인한다 (남으면 exit 1)
  eks.sh sweep              코어타임 밖이고 cluster 층이 남아 있으면 down (몇 번 돌아도 같은 상태로 수렴)
  eks.sh keep-up <요일1-7> <HH:MM> <YYYY-MM-DD> [hold]   지금 클러스터를 유지할 시간인지 (0 = 유지)
USAGE
  exit 2
}

log() { echo "eks.sh: $*" >&2; }
die() { log "$*"; exit 1; }

account_id() {
  [[ -n "${TF_VAR_aws_account_id:-}" ]] || TF_VAR_aws_account_id="$(aws sts get-caller-identity --query Account --output text)"
  export TF_VAR_aws_account_id
}

tf() { terraform -chdir="$CLUSTER" "$@"; }
tf_init() {
  account_id
  tf init -input=false -reconfigure -backend-config=backend.hcl \
    -backend-config="bucket=$NAME-tfstate-$TF_VAR_aws_account_id" >/dev/null
}
caller_cidr() { echo "$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32"; }

cluster_status() {
  aws eks describe-cluster --region "$REGION" --name "$NAME" --query cluster.status --output text 2>/dev/null || echo NONE
}

# 실행하는 곳(맥, GitHub Actions 러너)의 IP 가 공개 엔드포인트 허용 목록에 없으면 더하고 반영될 때까지 기다린다
ensure_endpoint_access() {
  local me cidrs id status
  me="$(caller_cidr)"
  cidrs="$(aws eks describe-cluster --region "$REGION" --name "$NAME" \
    --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text | tr '\t' ',')"
  [[ ",$cidrs," == *",$me,"* ]] && return
  log "adding $me to endpoint allow list ($cidrs)"
  id="$(aws eks update-cluster-config --region "$REGION" --name "$NAME" \
    --resources-vpc-config "publicAccessCidrs=$cidrs,$me" --query update.id --output text)"
  while status="$(aws eks describe-update --region "$REGION" --name "$NAME" --update-id "$id" --query update.status --output text)"; [[ "$status" == InProgress ]]; do
    sleep 15
  done
  [[ "$status" == Successful ]] || die "endpoint update $id: $status"
}

kubeconfig() {
  # 운영자의 ~/.kube/config 를 건드리지 않는다
  KUBECONFIG="$(mktemp)"
  export KUBECONFIG
  aws eks update-kubeconfig --region "$REGION" --name "$NAME" --kubeconfig "$KUBECONFIG" >/dev/null
}

up() {
  local start=$SECONDS
  tf_init
  tf apply -input=false -auto-approve -lock-timeout=5m -var "caller_cidr=$(caller_cidr)"
  kubeconfig
  kubectl wait --for=condition=Ready nodes --all --timeout=10m
  kubectl get nodes -L role
  log "up took $((SECONDS - start))s"
  tf output
}

# Terraform 밖에서 생긴 AWS 리소스(NLB, EBS)를 남기지 않게 지운다. NLB 는 LB Controller 가 살아 있을 때 지워야 따라 지워진다
drain() {
  if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
    # Argo CD 가 지운 Service 를 되살리지 않게 앱부터 지운다
    kubectl delete applications --all -n argocd --wait=false
    local deadline=$((SECONDS + 900))
    while [[ -n "$(kubectl get applications -n argocd -o name)" ]]; do
      ((SECONDS < deadline)) || die "argocd applications still exist after 15m"
      # Argo CD 는 동기화 중인 앱을 지우지 않는다. 끝나지 않는 동기화가 삭제를 막지 않게 끝낸다
      kubectl get applications -n argocd -o json |
        jq -r '.items[] | select(.status.operationState.phase == "Running") | .metadata.name' |
        while read -r app; do
          kubectl patch application "$app" -n argocd --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null
        done
      sleep 10
    done
  fi
  kubectl get svc -A -o json |
    jq -r '.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
    while read -r ns svc; do kubectl delete svc -n "$ns" "$svc" --timeout=5m; done
  # StatefulSet 의 PVC 는 Argo CD 가 지우지 않는다. EBS CSI 가 볼륨을 지울 때까지 PV 를 기다린다
  kubectl delete pvc --all -A --timeout=10m
  [[ -z "$(kubectl get pv -o name)" ]] || kubectl wait --for=delete pv --all --timeout=10m
}

down() {
  local start=$SECONDS status
  status="$(cluster_status)"
  if [[ "$status" == ACTIVE ]]; then
    ensure_endpoint_access
    kubeconfig
    drain
  else
    log "cluster status $status: skipping in-cluster cleanup"
  fi
  tf_init
  tf destroy -input=false -auto-approve -lock-timeout=5m -var "caller_cidr=$(caller_cidr)"
  log "down took $((SECONDS - start))s"
  leftovers
}

leftovers() {
  local found=() arns arn state
  # 조회가 실패하면 "0개"로 읽지 않고 멈춘다. && 와 pipefail 이 실패를 넘긴다
  arns="$(
    {
      aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=Project,Values=$NAME" Key=Layer,Values=cluster \
        --query 'ResourceTagMappingList[].ResourceARN' --output text &&
        aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=elbv2.k8s.aws/cluster,Values=$NAME" \
          --query 'ResourceTagMappingList[].ResourceARN' --output text &&
        aws resourcegroupstaggingapi get-resources --region "$REGION" --tag-filters "Key=kubernetes.io/cluster/$NAME" \
          --query 'ResourceTagMappingList[].ResourceARN' --output text &&
        # VPC CNI 가 만든 ENI 는 Project 태그가 없다
        aws ec2 describe-network-interfaces --region "$REGION" --filters "Name=tag:cluster.k8s.amazonaws.com/name,Values=$NAME" \
          --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
    } | tr '\t' '\n' | sort -u
  )" || die "listing resources failed"
  while read -r arn; do
    [[ -n "$arn" ]] || continue
    # 종료된 인스턴스, 삭제된 NAT 는 destroy 뒤에도 한동안 태그 API 에 남는다
    case "$arn" in
      *:instance/i-*)
        state="$(aws ec2 describe-instances --region "$REGION" --instance-ids "${arn##*/}" \
          --query 'Reservations[].Instances[].State.Name' --output text 2>&1 || true)"
        [[ "$state" == terminated || "$state" == *InvalidInstanceID.NotFound* ]] && continue ;;
      *:natgateway/nat-*)
        state="$(aws ec2 describe-nat-gateways --region "$REGION" --nat-gateway-ids "${arn##*/}" \
          --query 'NatGateways[].State' --output text 2>&1 || true)"
        [[ "$state" == deleted || "$state" == *NotFound* ]] && continue ;;
    esac
    found+=("$arn")
  done <<<"$arns"
  log "leftovers: ${#found[@]}"
  [[ ${#found[@]} -eq 0 ]] || { printf '%s\n' "${found[@]}"; return 1; }
}

# 0 = 유지할 시간. 평일 UP_AT 부터 CORE_END 까지. hold 는 오늘 날짜의 "YYYY-MM-DDTHH:MM" 일 때만 HOLD_MAX 까지 연장한다
keep_up() {
  local dow="$1" now="$2" today="$3" hold="${4:-}" end="$CORE_END"
  if [[ "$hold" =~ ^${today}T([0-2][0-9]:[0-5][0-9])$ ]]; then
    local h="${BASH_REMATCH[1]}"
    [[ "$h" > "$HOLD_MAX" ]] && h="$HOLD_MAX"
    [[ "$h" > "$end" ]] && end="$h"
  fi
  ((dow <= 5)) && [[ ! "$now" < "$UP_AT" && "$now" < "$end" ]]
}

sweep() {
  if keep_up "$(TZ=Asia/Seoul date +%u)" "$(TZ=Asia/Seoul date +%H:%M)" "$(TZ=Asia/Seoul date +%F)" "${EKS_HOLD_UNTIL:-}"; then
    log "inside core time (hold: ${EKS_HOLD_UNTIL:-none}), keeping cluster"
  elif leftovers >/dev/null && [[ "$(cluster_status)" == NONE ]]; then
    log "outside core time, nothing left"
  else
    down
  fi
}

case "${1:-}" in
  up) [[ $# -eq 1 ]] || usage; up ;;
  down) [[ $# -eq 1 ]] || usage; down ;;
  drain) [[ $# -eq 1 ]] || usage; drain ;;
  leftovers) [[ $# -eq 1 ]] || usage; leftovers ;;
  sweep) [[ $# -eq 1 ]] || usage; sweep ;;
  keep-up) [[ $# -ge 4 ]] || usage; keep_up "$2" "$3" "$4" "${5:-}" ;;
  *) usage ;;
esac
