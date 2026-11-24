# INFRA-maemusae

매무새 EKS 환경의 인프라와 배포 정의입니다. Argo CD는 이 레포의 `gitops/`만 바라봅니다. Terraform 구성은 인프라 리드가 정리한 EKS Terraform 자원 정리 문서를 기준으로 합니다.

| 경로 | 내용 | 담당 |
| --- | --- | --- |
| `terraform/bootstrap/` | state 버킷, GitHub OIDC 공급자, INFRA plan/apply 역할. 계정마다 한 번 적용 | infra |
| `terraform/modules/` | `network`, `rds`, `eks`, `pod-identity`, `platform`. 아래 층들이 부르는 모듈 | infra |
| `terraform/envs/dev/10-base/` | 늘 켜 두는 층. VPC, NAT 용 EIP, RDS 3개와 경보, S3, ECR, Secrets Manager, SES, CloudTrail, 예산, Pod Identity 역할, ECR push 역할 | infra |
| `terraform/envs/dev/20-eks/` | 코어타임 층. NAT Gateway, EKS, 노드그룹 2개, 애드온, Pod Identity 연결 | infra |
| `terraform/envs/dev/30-platform/` | 코어타임 층. LB Controller, External Secrets, ExternalDNS(도메인이 있을 때), Argo CD | infra |
| `terraform/eks.sh` | 코어타임 층 올리기, 내리기, 남은 리소스 확인 | infra |
| `gitops/` | Argo CD app-of-apps, 앱과 관측 스택 values (아직 없음) | infra |
| `gitops/security/` | 보안 정책, kube-bench, NetworkPolicy (아직 없음) | security |
| `iam/policies/` | Terraform 이 읽는 IAM 정책 문서 | security, infra |

층마다 state 가 따로라서 `20-eks` 와 `30-platform` 만 매일 만들고 지웁니다. 두 층은 `terraform_remote_state` 로 `10-base` 를, `30-platform` 은 `20-eks` 도 읽습니다. 자원 정리 문서의 항목이 어느 파일에 있는지, 문서와 다른 점은 [docs/architecture.md](docs/architecture.md)에 있습니다. 레포 구조를 정한 배경은 [SPEC adr/0001](https://github.com/saebyeok-baesong/SPEC-maemusae/blob/main/adr/0001-repo-structure.md)을 보세요.

## 처음 적용하기

적용 순서는 bootstrap, 10-base, 20-eks, 30-platform 입니다. 공개 저장소라 계정 ID 와 메일 주소는 파일에 두지 않고 환경 변수로 넘깁니다. 아래 명령은 Terraform 1.11.1 이상과 관리자 권한의 AWS 자격 증명이 있다고 가정합니다.

```sh
export TF_VAR_aws_account_id=<12자리 계정 ID>
export TF_VAR_alert_email=<예산 알림과 RDS 경보를 받을 메일>
```

1. bootstrap 을 로컬 state 로 적용합니다. 계정에 GitHub OIDC 공급자가 이미 있으면 `-var create_github_oidc_provider=false` 를 붙입니다.

	```sh
	terraform -chdir=terraform/bootstrap init
	terraform -chdir=terraform/bootstrap apply
	```

2. bootstrap output 과 아래 값을 GitHub 저장소 설정에 넣습니다.
	- 변수 `AWS_ACCOUNT_ID`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`
	- 비밀 `ALERT_EMAIL`
	- Environment `production` 에 승인 규칙, Environment `eks` 에 배포 브랜치 `main` 제한
	- 변수 `EKS_ADMIN_PRINCIPAL_ARNS` 에 클러스터 관리자 ARN 목록을 JSON 으로. 예: `["arn:aws:iam::<계정>:role/maemusae-gha-apply"]`

3. 10-base 를 적용합니다. 이후에는 `main` 에 merge 하면 `.github/workflows/terraform.yml` 이 `production` 승인 뒤 적용합니다. 적용 뒤 SNS 확인 메일의 링크를 눌러야 RDS 경보가 옵니다.

	```sh
	terraform -chdir=terraform/envs/dev/10-base init -backend-config=backend.hcl -backend-config="bucket=maemusae-tfstate-$TF_VAR_aws_account_id"
	terraform -chdir=terraform/envs/dev/10-base apply
	```

4. Secrets Manager 비밀에 값을 넣습니다. 10-base 는 빈 비밀(`maemusae/openai`, `maemusae/discord`)만 만들고, 값은 state 에 남지 않게 CLI 로 넣습니다.

	```sh
	aws secretsmanager put-secret-value --secret-id maemusae/openai --secret-string file://openai.json
	```

5. 20-eks 와 30-platform 을 올립니다. 평일 13:40 KST 에 `.github/workflows/eks.yml` 이 자동으로 올리게 하려면 저장소 변수 `EKS_SCHEDULE_ENABLED=true` 를 넣습니다.

	```sh
	terraform/eks.sh up
	```

bootstrap state 를 S3 로 옮기려면 `terraform/bootstrap/versions.tf` 에 `backend "s3" {}` 를 더하고 key `bootstrap/terraform.tfstate` 로 `init -migrate-state` 합니다.

## 코어타임에 올리고 내리기

`eks.sh` 는 수동 실행과 GitHub Actions 스케줄이 같이 씁니다.

| 명령 | 하는 일 |
| --- | --- |
| `eks.sh up` | 20-eks apply, 노드 Ready 대기, 30-platform apply |
| `eks.sh down` | Argo CD 앱 삭제, LoadBalancer Service 와 PVC 정리, ExternalDNS 레코드가 지워질 때까지 대기, 30-platform destroy, 20-eks destroy, 남은 리소스 확인 |
| `eks.sh sweep` | 코어타임 밖이면 `down`. 매시 5분, 35분에 스케줄이 부릅니다 |
| `eks.sh leftovers` | `Layer=eks` 태그(NAT Gateway 포함), LB Controller 태그, VPC CNI ENI 가 남았는지 확인 |

코어타임은 평일 13:40 부터 17:30 까지(KST)입니다. `UP_AT`, `CORE_END` 환경 변수로 바꿉니다. 저장소 변수 `EKS_HOLD_UNTIL` 에 `2026-11-24T21:00` 처럼 오늘 날짜와 시각을 넣으면 그날만 `HOLD_MAX`(기본 22:00)까지 늘어납니다.

`down` 은 층을 지우기 전에 클러스터 안부터 정리합니다. NLB 는 LB Controller 가, Route53 레코드는 ExternalDNS 가 만들어서, 두 컨트롤러가 살아 있을 때 Service 를 지워야 NLB 와 레코드도 지워집니다. 클러스터가 이미 없으면 30-platform state 의 Helm 릴리스만 비우고 20-eks 를 destroy 합니다.

## 로컬 검사

AWS 에 접속하지 않고 root 모듈을 검사합니다. `terraform test` 는 mock provider 로 plan 합니다(`modules/network` 는 mock apply).

```sh
terraform fmt -check -recursive terraform
for d in bootstrap modules/network envs/dev/10-base envs/dev/20-eks envs/dev/30-platform; do
	terraform -chdir=terraform/$d init -backend=false
	terraform -chdir=terraform/$d validate
done
for d in modules/network envs/dev/10-base envs/dev/20-eks envs/dev/30-platform; do
	terraform -chdir=terraform/$d test
done
```

CI 는 같은 검사에 tflint(`terraform/.tflint.hcl`)를 더하고, PR 에서는 10-base 를 plan 합니다.
