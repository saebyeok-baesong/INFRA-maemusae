# 아키텍처와 Terraform 대응

리전은 ap-northeast-2, VPC 는 하나입니다. Terraform 은 늘 켜 두는 `base` 층과 코어타임에만 띄우는 `cluster` 층으로 나뉩니다. 두 층은 state 가 따로라서 `eks.sh down` 이 `cluster` 를 지워도 `base` 의 데이터는 남습니다.

## 다이어그램 상자별 위치

| 다이어그램 상자 | 위치 | 리소스 |
| --- | --- | --- |
| VPC, IGW | base | `module.vpc` (`terraform/base/network.tf`) |
| 퍼블릭 서브넷 2a | base | `module.vpc` public_subnets. 태그 `kubernetes.io/role/elb=1` |
| 프라이빗 서브넷 2a, 2c | base | `module.vpc` private_subnets. 태그 `kubernetes.io/role/internal-elb=1` |
| NAT Gateway | cluster | `aws_nat_gateway.this`, `aws_eip.nat`, `aws_route.private_nat` |
| S3 Gateway endpoint | base | `aws_vpc_endpoint.s3` |
| NLB | k8s | Traefik Service(type LoadBalancer)를 보고 AWS LB Controller 가 만듭니다 |
| EKS 컨트롤 플레인 | cluster | `module.eks` |
| app 노드그룹 (2a, t4g.large, role=app) | cluster | `module.eks` eks_managed_node_groups, 변수 `node_groups.app` |
| platform 노드그룹 (2c, t4g.large, role=platform) | cluster | `module.eks` eks_managed_node_groups, 변수 `node_groups.platform` |
| migrate Job, Traefik, Web, BE x2 | gitops 예정 | |
| incident 네임스페이스 (Webhook API, Redis Streams, LangGraph worker, approvals) | gitops 예정 | |
| Argo CD | cluster | `helm_release.argocd` (platform 노드) |
| External Secrets, AWS LB Controller, ExternalDNS | gitops 예정 | IAM 역할은 base, Pod Identity 연결은 cluster |
| kube-bench, Alloy, Loki, Grafana, Prometheus, Alertmanager, kube-state-metrics, metrics-server, node-exporter | gitops 예정 | Loki 의 S3 역할만 base |
| CoreDNS, VPC CNI, kube-proxy, Pod Identity Agent, EBS CSI | cluster | `module.eks` addons |
| RDS security, incident, service | base | `aws_db_instance.this` (변수 `databases`) |
| DB 서브넷 그룹 a+c | base | `aws_db_subnet_group.this` |
| RDS 보안 그룹 (5432, EKS 노드에서만) | base | `aws_security_group.rds`, `aws_security_group.eks_clients` |
| S3 uploads, Loki | base | `aws_s3_bucket.this["uploads"]`, `aws_s3_bucket.this["loki"]` |
| ECR | base | `aws_ecr_repository.this` (변수 `ecr_repositories`: web, api, ops) |
| Secrets Manager | base | `aws_secretsmanager_secret.app` (`maemusae/service`, `maemusae/ops`), RDS 가 관리하는 마스터 비밀 3개 |
| SES | base | `aws_sesv2_email_identity.report`. `ses_domain` 이 있을 때만 |
| CloudWatch | 리소스 없음 | RDS, NLB 기본 지표는 AWS 가 자동으로 모읍니다 |
| CloudTrail | base | `aws_cloudtrail.this`, `aws_s3_bucket.this["cloudtrail"]` |
| AWS Budgets 50/70/100% | base | `aws_budgets_budget.monthly` |
| GitHub OIDC, INFRA plan/apply 역할 | bootstrap | `module.github_oidc`, `module.plan_role`, `module.apply_role` |
| SERVICE, OPS 의 ECR push 역할 | base | `aws_iam_role.ecr_push` (GitHub 저장소마다 하나, `main` 브랜치만) |
| 워크로드 IAM 역할 | base | `aws_iam_role.workload`. 정책 문서는 `iam/policies/` |

## base 가 내보내고 cluster 가 읽는 값

cluster 는 `terraform_remote_state` 로 base state 를 읽습니다. 버킷 이름은 `maemusae-tfstate-<계정 ID>`, key 는 `base/terraform.tfstate` 입니다. SSM 파라미터 대신 remote state 를 고른 이유는 apply 역할이 이미 state 버킷을 읽을 수 있어서 권한과 리소스를 더 만들지 않아도 되기 때문입니다.

| output | 모양 | cluster 에서 쓰는 곳 |
| --- | --- | --- |
| `name` | `"maemusae"` | 클러스터 이름, 태그 |
| `vpc_id` | 문자열 | EKS |
| `public_subnet_ids` | 목록 | NAT 를 첫 번째 서브넷(2a)에 |
| `private_subnet_ids_by_az` | AZ => 서브넷 ID | 컨트롤 플레인은 전부, 노드그룹은 `node_groups[*].az` 로 하나씩 |
| `private_route_table_ids` | 목록 | NAT 기본 경로를 더할 곳 |
| `eks_clients_security_group_id` | 문자열 | 모든 노드에 붙입니다. RDS 가 이 그룹만 받습니다 |
| `workload_identities` | 키 => namespace, service_account, role_arn | `aws_eks_pod_identity_association.workload` |
| `ebs_csi_role_arn` | 문자열 | EBS CSI 애드온 |

나머지 output(`ecr_repository_urls`, `ecr_push_role_arns`, `bucket_names`, `databases`, `app_secret_names`)은 gitops values 와 다른 레포 CI 설정에 옮겨 적을 값입니다. cluster 는 읽지 않습니다.

`workload_identities` 의 namespace 와 서비스 계정 이름은 gitops 매니페스트와의 계약입니다.

| 키 | namespace/서비스 계정 | 권한 |
| --- | --- | --- |
| `aws-load-balancer-controller` | `kube-system/aws-load-balancer-controller` | 업스트림 v3.6.3 정책 그대로 |
| `external-secrets` | `external-secrets/external-secrets` | `maemusae/*` 비밀과 RDS 마스터 비밀 읽기 |
| `loki` | `monitoring/loki` | Loki 버킷 읽기, 쓰기, 삭제 |
| `api` | `maemusae/api` | uploads 버킷 읽기, 쓰기, 삭제 |
| `external-dns` | `external-dns/external-dns` | `route53_zone_id` 영역의 레코드 변경. 영역 ID 가 있을 때만 만듭니다 |

## 층을 이렇게 나눈 이유

**VPC 는 base 에 있습니다.** RDS 가 늘 켜져 있어서 서브넷과 보안 그룹도 늘 있어야 합니다. infra_template 의 aiops-eks 는 RDS 가 없어서 VPC 를 cluster 층에 두었는데, 여기서는 그대로 따를 수 없습니다.

**NAT 는 cluster 에 있습니다.** NAT 는 노드가 ECR, OpenAI, Discord 로 나갈 때만 필요하고 시간당 요금이 붙습니다. RDS 는 NAT 를 쓰지 않습니다. 그래서 NAT 와 EIP 는 클러스터와 함께 만들고 지우고, base 의 private 라우팅 테이블에 기본 경로만 더합니다. 컨트롤 플레인 생성에 10분 남짓 걸리고 NAT 는 2분 안에 끝나서, 노드가 뜰 때는 NAT 경로가 이미 있습니다.

**RDS 는 고정 보안 그룹 하나만 믿습니다.** 노드 보안 그룹은 클러스터를 다시 만들 때마다 ID 가 바뀝니다. 그래서 base 가 `maemusae-eks-clients` 그룹을 만들고, cluster 가 모든 노드그룹에 이 그룹을 붙입니다. VPC CNI 기본 설정에서 Pod 는 노드 ENI 의 보안 그룹을 쓰므로, 이 그룹이 붙은 노드의 Pod 는 RDS 5432 에 닿습니다.

**두 노드그룹 모두 taint 가 있습니다.** `role=app:NoSchedule`, `role=platform:NoSchedule` 입니다. toleration 이 없는 Pod 는 어디에도 뜨지 못하므로, cluster 층은 CoreDNS, EBS CSI 컨트롤러, Argo CD 에 platform toleration 과 nodeSelector 를 넣습니다. gitops 로 설치할 애드온과 앱도 같은 toleration 이 필요합니다. DaemonSet(node-exporter, Alloy)은 두 taint 를 모두 견뎌야 합니다.

**RDS 비밀번호는 RDS 가 관리합니다.** `manage_master_user_password = true` 라 비밀번호가 Terraform state 에 남지 않고, Secrets Manager 에 `rds!db-...` 이름으로 생깁니다. External Secrets 가 이 비밀을 읽어 앱에 넘깁니다. pgvector 는 incident DB 에서 앱이나 migrate Job 이 `CREATE EXTENSION vector` 로 켭니다.

## Argo CD 와 애드온 설치

cluster 층은 Argo CD 만 Helm 으로 설치합니다. infra_template 도 Argo CD 와 루트 앱을 Helm 으로 설치했습니다. 루트 앱은 `gitops/` 가 생긴 뒤에 더합니다. LB Controller, External Secrets, ExternalDNS, 관측 스택, kube-bench 는 Argo CD 가 `gitops/` 에서 설치합니다. 이 애드온들의 IAM 역할과 Pod Identity 연결은 Terraform 이 미리 만들어 둡니다.

## 운영 결정 (2026-11-25)

| 항목 | 결정 | 다시 볼 때 |
| --- | --- | --- |
| 가용 영역 | 퍼블릭 서브넷, NAT, app 노드 모두 2a 하나. 비용 절감을 위해 2a 장애 시 서비스와 egress가 같이 끊기는 것을 받아들인다 | 운영 트래픽을 받을 때 `public_subnet_cidrs`에 2c를 더하고 app 노드를 2c에도 둔다 |
| 코어타임 | 평일 14:00~17:30 KST. 정리 cron이 30분마다 돌아 17:35 전후에 내려간다 | 팀 일정이 바뀌면 `eks.sh`의 `UP_AT`, `CORE_END`와 `eks.yml`의 올리기 cron을 함께 바꾼다 |
| 도메인 | 아직 없음. `route53_zone_id`, `ses_domain`이 비어 있어 ExternalDNS 역할과 SES 도메인을 만들지 않는다 | 도메인을 산 뒤 두 변수를 채운다 |
| CloudTrail | 2026-11-25에 계정에서 `describe-trails --include-shadow-trails`(ap-northeast-2)로 확인한 결과 trail이 없다. 이 trail이 첫 trail이라 관리 이벤트 사본 과금이 없다 | 다른 팀이 trail을 만들면 하나로 합친다 |
| apply 역할 권한 | PowerUser와 IAMFull을 유지한다 | 보안팀과 합의해 줄인다 |
