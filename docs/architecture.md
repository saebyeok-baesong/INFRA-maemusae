# 아키텍처와 Terraform 대응

기준 문서는 인프라 리드가 정리한 `EKS_Terraform_리소스정리.md`(이하 자원 정리 문서)입니다. 리전은 ap-northeast-2, VPC 는 하나입니다. Terraform 은 늘 켜 두는 `10-base` 와 코어타임에만 띄우는 `20-eks`, `30-platform` 으로 나뉩니다. 층마다 state 가 따로라서 `eks.sh down` 이 두 코어타임 층을 지워도 `10-base` 의 데이터는 남습니다.

```
terraform/
├── bootstrap/            state 버킷, GitHub OIDC 공급자, plan/apply 역할
├── modules/
│   ├── network/          VPC, 퍼블릭/노드/DB 서브넷, IGW, 라우팅 테이블, S3 endpoint, NAT 용 EIP, 노드/RDS 보안 그룹
│   ├── rds/              RDS 1대와 그 경보, IAM DB 인증 (10-base 가 for_each 로 2번 부른다, AZ 는 변수)
│   ├── eks/              클러스터, 노드그룹, 애드온, Access Entry
│   ├── pod-identity/     컴포넌트별 IAM 역할
│   └── platform/         Helm 릴리스 (LB Controller, External Secrets, ExternalDNS, Argo CD)
├── envs/dev/
│   ├── 10-base/          상시
│   ├── 20-eks/           코어타임: NAT Gateway, eks 모듈, Pod Identity 연결
│   └── 30-platform/      코어타임: platform 모듈
├── lambda/discord-alerts/  alerts 주제를 Discord 로 보내는 Lambda 코드와 자체 검사 (10-base 가 묶어 올린다)
└── sql/                  ops 인스턴스의 DB 와 IAM 인증 역할. 사람이 한 번 실행한다
```

## 문서 항목별 위치

| 문서 항목 | 층 | 파일과 리소스 |
| --- | --- | --- |
| §2.1 VPC (DNS hostnames/support) | 10-base | `modules/network/main.tf` `aws_vpc.this` |
| §2.1 Public subnet 2a, 태그 `elb=1` | 10-base | `aws_subnet.public` (변수 `public_subnet`) |
| §2.1 Private subnet 2a, 2c, 태그 `internal-elb=1` | 10-base | `aws_subnet.private` (변수 `private_subnets`) |
| 문서에 없음. DB 서브넷 2a, 2c | 10-base | `aws_subnet.db` (변수 `db_subnets`) |
| 문서에 없음. DB 라우팅 테이블 (local 경로만) | 10-base | `aws_route_table.db`, `aws_route_table_association.db` |
| §2.1 Internet Gateway | 10-base | `aws_internet_gateway.this` |
| §2.1 NAT Gateway | 20-eks | `envs/dev/20-eks/main.tf` `aws_nat_gateway.this` |
| §2.1 NAT 용 EIP | 10-base | `modules/network/main.tf` `aws_eip.nat` |
| §2.1 Route Table public (`0.0.0.0/0 → IGW`) | 10-base | `aws_route_table.public` |
| §2.1 Route Table private (2a, 2c 공용) | 10-base | `aws_route_table.private`, `aws_route_table_association.private` |
| §2.1 private 기본 경로 `0.0.0.0/0 → NAT` | 20-eks | `aws_route.private_nat` |
| §2.1 S3 Gateway Endpoint (private 라우팅 테이블) | 10-base | `aws_vpc_endpoint.s3` |
| §2.3 EKS cluster SG | 20-eks | EKS 가 클러스터를 만들 때 자동으로 만든다 |
| §2.3 EKS node SG (노드 간, NLB 헬스체크) | 10-base | `aws_security_group.node` 와 규칙 3개. 20-eks 가 노드에 붙인다 |
| §2.3 RDS SG (5432 from node SG) | 10-base | `aws_security_group.rds`, `aws_vpc_security_group_ingress_rule.rds_from_node` |
| §3.1 클러스터, private 2a+2c | 20-eks | `modules/eks/main.tf` `aws_eks_cluster.this` |
| §3.1 Access Entry | 20-eks | `access_config` (API 모드), `aws_eks_access_entry.admin`, `aws_eks_access_policy_association.admin` |
| §3.1 Pod Identity 연결 | 20-eks | `envs/dev/20-eks/main.tf` `aws_eks_pod_identity_association.this` |
| §3.1 애드온 5개 | 20-eks | `aws_eks_addon.before_nodes` (vpc-cni, kube-proxy, eks-pod-identity-agent), `aws_eks_addon.after_nodes` (coredns, aws-ebs-csi-driver) |
| §3.2 노드그룹 platform(2c), app(2a), t4g.large, AL2023 ARM64, `role` 라벨과 taint | 20-eks | `aws_eks_node_group.this`, `aws_launch_template.node` (변수 `node_groups`) |
| §3.3 코어타임 생성, 삭제 순서 | - | `terraform/eks.sh`, `.github/workflows/eks.yml` |
| §4.1 LB Controller, External Secrets, ExternalDNS, Argo CD | 30-platform | `modules/platform/main.tf` `helm_release.*` |
| §4.1 나머지 (kube-bench, Alloy, Loki, Grafana, Prometheus, Alertmanager, kube-state-metrics, metrics-server, node-exporter) | gitops 예정 | Argo CD 가 설치한다. Loki 의 IAM 역할만 10-base |
| §4.2, §4.3 앱과 incident 네임스페이스 | gitops 예정 | |
| §5.1 RDS x3, db.t4g.micro, 서브넷 그룹 하나, `manage_master_user_password` | 10-base | `envs/dev/10-base/data.tf` `module.rds` 2개 service, ops (변수 `databases`, `rds_availability_zone`), `aws_db_subnet_group.this` (DB 서브넷만). ops 안의 incident, security DB 와 역할은 `terraform/sql/ops-db-roles.sql` |
| 문서에 없음. RDS 이벤트 알림 | 10-base | `aws_db_event_subscription.rds` → `aws_sns_topic.alerts` |
| 문서에 없음. 경보 Discord 전달 | 10-base | `aws_lambda_function.discord_alerts` (코드 `terraform/lambda/discord-alerts/main.py`), `aws_sns_topic_subscription.alerts_discord`, `aws_cloudwatch_log_group.discord_alerts`. 정책은 `iam/policies/discord-alerts.json.tftpl` |
| 문서에 없음. Prometheus 데이터 볼륨 | 10-base | `aws_ebs_volume.prometheus` (변수 `prometheus_volume`). 붙이는 PV 는 gitops 예정 |
| §5.2 S3 uploads, loki 와 문서에 없는 security-scans (퍼블릭 차단, SSE, 수명 주기) | 10-base | `aws_s3_bucket.this` public, private 2개, `..._public_access_block`, `..._server_side_encryption_configuration`, `aws_s3_bucket_policy.public`, `aws_s3_bucket_lifecycle_configuration.private` (접두사표 `local.private_prefixes`). 아래 "S3 버킷" |
| §6 ECR 4개(web, api, migrate, ops) + 수명 주기 | 10-base | `envs/dev/10-base/services.tf` `aws_ecr_repository.this`, `aws_ecr_lifecycle_policy.this` (변수 `ecr_repositories`) |
| §6 Secrets Manager | 10-base | `aws_secretsmanager_secret.app` (`maemusae/openai`, `maemusae/discord`, `maemusae/github-rollback-app`, `maemusae/discord-alerts-webhook`). DB 접속 정보는 RDS 가 만드는 마스터 비밀 2개 |
| §6 SES + DKIM 레코드 | 10-base | `aws_sesv2_email_identity.report`, `aws_route53_record.ses_dkim`. 도메인이 있을 때만 |
| §6 CloudWatch 경보 | 10-base | `modules/rds/main.tf` `aws_cloudwatch_metric_alarm.this` (DB 마다 CPU, 남은 저장 공간, 연결 수), `aws_sns_topic.alerts` |
| §6 CloudTrail + S3 | 10-base | `aws_cloudtrail.this` (`s3_key_prefix = "cloudtrail"`), `aws_s3_bucket_policy.private` |
| §6 Budgets 50/70/100% | 10-base | `aws_budgets_budget.monthly` |
| §6 Route53 영역 | 10-base | 변수 `route53_zone_id`. 비어 있으면 ExternalDNS 와 DKIM 레코드를 만들지 않는다 |
| §7 EKS 클러스터 역할, 노드 역할 | 20-eks | `modules/eks/main.tf` `aws_iam_role.cluster`, `aws_iam_role.node` (SSM `AmazonSSMManagedInstanceCore` 포함) |
| §7 Pod Identity 역할 7개 (external-dns 는 영역이 있을 때) | 10-base | `envs/dev/10-base/iam.tf` `module.pod_identity`. 정책 문서는 `iam/policies/` |
| §7 GitHub OIDC, Terraform apply 역할 | bootstrap | `module.github_oidc`, `module.plan_role`, `module.apply_role` |
| §7 GitHub OIDC ECR push 역할 (SERVICE, OPS) | 10-base | `aws_iam_role.ecr_push` (GitHub 저장소마다 하나, `main` 브랜치만) |
| 문서에 없음. 보안 스캔 업로드 역할 (SERVICE, OPS, INFRA) | 10-base | `aws_iam_role.scan_upload` (변수 `security_scan_repositories`). 정책은 `iam/policies/github-security-scan-upload.json.tftpl` |

## 층 사이 계약

20-eks 와 30-platform 은 `terraform_remote_state` 로 앞 층의 state 를 읽습니다. 버킷은 `maemusae-tfstate-<계정 ID>`, key 는 `dev/<층>/terraform.tfstate` 입니다.

| 10-base output | 읽는 층 | 쓰는 곳 |
| --- | --- | --- |
| `name`, `region` | 20-eks, 30-platform | 클러스터 이름, 태그, Helm values |
| `vpc_id` | 30-platform | LB Controller `vpcId` |
| `public_subnet_id`, `nat_eip_allocation_id` | 20-eks | NAT Gateway |
| `private_route_table_id` | 20-eks | NAT 기본 경로 |
| `private_subnet_ids_by_az` | 20-eks | 컨트롤 플레인은 전부, 노드그룹은 `node_groups[*].az` 로 하나씩 |
| `node_security_group_id` | 20-eks | 모든 노드의 시작 템플릿 |
| `pod_identities` | 20-eks, 30-platform | 20-eks 는 연결을 만들고, 30-platform 은 서비스 계정 이름을 Helm values 에 넣는다 |
| `route53_zone_id` | 30-platform, `eks.sh` | ExternalDNS 영역, down 의 레코드 정리 대기 |

20-eks 는 `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data` 를 내고 30-platform 의 Helm 공급자가 읽습니다. 나머지 10-base output(`nat_public_ip`, `ecr_repository_urls`, `ecr_push_role_arns`, `security_scan_bucket`, `security_scan_prefix`, `security_scan_role_arns`, `bucket_names`, `databases`, `prometheus_volume`, `app_secret_names`)은 gitops values 와 다른 레포 CI 설정에 옮겨 적을 값입니다.

`pod_identities` 의 namespace 와 서비스 계정 이름은 Helm values, gitops 매니페스트와의 계약입니다.

| 키 | namespace/서비스 계정 | 권한 |
| --- | --- | --- |
| `aws-load-balancer-controller` | `kube-system/aws-load-balancer-controller` | 업스트림 v3.6.3 정책 그대로 |
| `external-secrets` | `external-secrets/external-secrets` | `maemusae/*` 비밀과 RDS 마스터 비밀 읽기 |
| `loki` | `monitoring/loki` | private 버킷 `loki/` 읽기, 쓰기, 삭제 |
| `api` | `maemusae/api` | public 버킷 전체와 private 버킷 `uploads/` 읽기, 쓰기, 삭제 |
| `ebs-csi` | `kube-system/ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
| `external-dns` | `external-dns/external-dns` | `route53_zone_id` 영역의 레코드 변경. 영역 ID 가 있을 때만 만든다 |
| `ops-security-ingest` | `incident/ops-security-ingest` | private 버킷 `security-scans/` 목록과 객체 읽기, ops DB 에 `security_app` 으로 IAM 접속 |
| `ops` | `incident/ops` | ops DB 에 `incident_app` 으로 IAM 접속 |

## 보안 스캔 업로드

SERVICE, OPS, INFRA 의 CI 가 스캔 결과 JSON 을 `maemusae-private-<계정 ID>` 버킷의 `security-scans/` 아래에 올리고, incident namespace 의 `ops-security-ingest` 가 읽습니다. 이 이름과 키 형식은 OPS, SPEC 과 맞춘 계약입니다.

- 객체 키는 `security-scans/<저장소>/<도구>/<YYYY-MM-DD>/<github_run_id>.json` 입니다. `<저장소>` 는 `SERVICE-watch-nyang`, `OPS-watch-nyang`, `INFRA-watch-nyang` 중 하나입니다.
- 저장소마다 역할 `maemusae-gha-scan-<저장소 이름 소문자>` 가 있고, 자기 `security-scans/<저장소>/*` 아래에만 `s3:PutObject` 할 수 있습니다. 다른 저장소의 결과를 덮어쓰거나 읽지 못합니다.
- trust 는 그 저장소의 `main` 브랜치 push 와 `pull_request` 입니다. fork PR 은 OIDC 토큰을 받지 못하므로 같은 저장소 브랜치의 PR 만 올릴 수 있습니다. 쓰기 권한이 있는 사람이 PR 에서 자기 저장소 접두사 아래에 결과를 꾸며 올릴 수는 있습니다. 결과만 쓰고 지우지 못하므로 받아들입니다.
- 객체는 90일 뒤 지웁니다(변수 `security_scan_retention_days`).

## S3 버킷

버킷은 둘입니다. 둘 다 SSE-S3 로 암호화하고 `force_destroy = false` 라 객체가 남아 있으면 지워지지 않습니다.

| 버킷 | 접두사 | 쓰는 곳 | 보관 |
| --- | --- | --- | --- |
| `maemusae-public-<계정 ID>` | 전체 | 공개 업로드. 누구나 `GetObject` 로 읽는다. 쓰기는 `api` 만 | 지우지 않는다 |
| `maemusae-private-<계정 ID>` | `uploads/` | 비공개 사용자 파일. `api` 가 presigned URL 로 내준다 | 지우지 않는다 |
| | `loki/` | Loki 청크와 인덱스 | `loki_retention_days`(14일) |
| | `cloudtrail/` | CloudTrail 로그 (`cloudtrail/AWSLogs/<계정 ID>/...`) | `cloudtrail_retention_days`(365일) |
| | `security-scans/` | 보안 스캔 결과. 위 "보안 스캔 업로드" | `security_scan_retention_days`(90일) |

public 버킷은 버킷 정책으로만 공개합니다. 버킷의 퍼블릭 차단은 `block_public_policy`, `restrict_public_buckets` 만 끄고 ACL 차단 두 개는 켜 둡니다. 소유권은 `BucketOwnerEnforced` 라 ACL 을 쓰지 않습니다. 계정 수준 S3 퍼블릭 액세스 차단이 켜져 있으면 버킷 설정보다 우선해서 정책을 넣을 수 없고 공개도 되지 않습니다. 10-base 를 적용하기 전에 계정 수준 차단의 `BlockPublicPolicy`, `RestrictPublicBuckets` 가 꺼져 있는지 확인합니다(`aws s3control get-public-access-block --account-id <계정 ID>`).

private 버킷의 Pod Identity 정책은 접두사로 나눕니다. 객체 권한은 `<접두사>/*` 에만 있고, `s3:ListBucket` 은 `s3:prefix` 조건으로 자기 접두사 목록만 볼 수 있습니다. 수명 주기 규칙은 접두사마다 하나이고, 끝나지 않은 멀티파트 업로드는 버킷 전체에서 하루 뒤 지웁니다.

Loki 는 3.4 부터 `storage_config.object_prefix` 로 모든 객체 키 앞에 접두사를 붙입니다(실험 기능, 기본 클라이언트 `use_thanos_objstore: false` 기준). gitops 의 Loki values 에서 버킷을 private 으로 두고 접두사를 `loki/` 로 줍니다. 접두사가 빠지면 Loki 가 버킷 루트에 쓰려다 IAM 에서 거부됩니다.

```yaml
storage_config:
  object_prefix: loki/
```

ECR push 역할에 이 권한을 더하지 않고 역할을 따로 둔 이유는 trust 가 달라서입니다. push 역할은 `main` 만 믿는데 스캔은 PR 에서도 돕니다. 합치면 PR 이 이미지를 push 할 수 있게 되거나, 스캔이 `main` 에서만 돕니다. INFRA 는 push 역할이 없고 plan, apply 역할은 권한이 넓어서 같은 형태의 작은 역할을 하나 둡니다.

## 설계 이유

**Pod Identity 역할은 10-base 에, 연결은 20-eks 에 있습니다.** 역할은 IAM 이라 클러스터와 상관없이 무료로 남겨 둘 수 있습니다. 매일 다시 만들지 않으니 ARN 이 그대로이고, 보안팀이 리뷰한 정책과 CloudTrail 기록이 이어집니다. External Secrets 정책은 10-base 의 RDS 마스터 비밀 ARN 을 써서 같은 층에 있는 편이 단순합니다. 연결은 클러스터가 있어야 만들 수 있어서 20-eks 에 둡니다.

**노드 보안 그룹은 10-base 에 있습니다.** RDS 보안 그룹이 이 그룹 ID 를 참조하는데, 클러스터와 함께 만들면 ID 가 매일 바뀝니다. 이 그룹이 자원 정리 문서 §2.3 의 EKS node SG 입니다. 노드 간 통신(자기 참조)과 퍼블릭 서브넷의 NLB 헬스체크를 받습니다. 20-eks 는 시작 템플릿에 이 그룹과 EKS 클러스터 보안 그룹을 함께 넣습니다. 시작 템플릿에 보안 그룹을 지정하면 EKS 가 클러스터 보안 그룹을 붙이지 않아서입니다. VPC CNI 기본 설정에서 Pod 는 노드 ENI 의 보안 그룹을 쓰므로, 노드의 Pod 가 RDS 5432 에 닿습니다. 노드 보안 그룹에는 `kubernetes.io/cluster/<이름>` 태그를 달지 않습니다. LB Controller 는 그 태그가 붙은 그룹 하나에 NLB 규칙을 넣는데, 그 자리는 EKS 클러스터 보안 그룹입니다.

**NAT Gateway 는 20-eks 에, EIP 는 10-base 에 있습니다.** 운영 결정 표를 보세요. 노드그룹은 NAT 경로가 생긴 뒤 만듭니다. 노드가 부팅하며 ECR 과 외부에서 이미지를 받아야 해서입니다. `node_subnet_ids_by_az` 를 경로 ID 를 거쳐 넘겨 노드그룹만 기다리게 하고, 컨트롤 플레인은 그동안 먼저 만들어집니다.

**두 노드그룹 모두 taint 가 있습니다.** `role=app:NoSchedule`, `role=platform:NoSchedule` 입니다. 자원 정리 문서는 "라벨/테인트 예시"로 적었지만, 노드 역할을 지키려고 taint 를 유지합니다. toleration 이 없는 Pod 는 어디에도 뜨지 못하므로 CoreDNS, EBS CSI 컨트롤러, 30-platform 의 차트 4개에 platform toleration 과 nodeSelector 를 넣습니다. gitops 로 설치할 애드온과 앱도 같은 toleration 이 필요합니다. DaemonSet(node-exporter, Alloy)은 두 taint 를 모두 견뎌야 합니다.

**노드 IMDS 홉 제한은 1 입니다.** Pod 가 노드 자격 증명을 IMDS 로 빌려 쓰지 못하게 합니다. 그래서 LB Controller 에 리전과 VPC ID 를 values 로 넘깁니다.

**RDS 는 DB 전용 서브넷에 있습니다.** DB 서브넷 2a, 2c 는 노드 서브넷과 다른 라우팅 테이블을 쓰고, 그 테이블에는 VPC 안 local 경로만 있습니다. 20-eks 가 NAT 기본 경로를 더하는 곳은 노드용 private 테이블이라 DB 서브넷에는 닿지 않습니다. RDS 는 인터넷으로 나갈 일이 없고, 보안 그룹은 그대로 노드 보안 그룹에서 오는 5432 만 받습니다. RDS 서브넷 그룹은 AZ 2개를 요구해서 2c 서브넷도 그룹에 넣지만, 인스턴스는 `rds_availability_zone`(2a)에 둡니다. 나중에 Multi-AZ 를 켜면 대기 인스턴스가 2c 에 생깁니다.

**RDS 비밀번호는 RDS 가 관리합니다.** `manage_master_user_password = true` 라 비밀번호가 Terraform state 에 남지 않고, Secrets Manager 에 `rds!db-...` 이름으로 생깁니다. External Secrets 가 이 비밀을 읽어 앱에 넘깁니다.

**pgvector 는 ops DB 역할 SQL 이 켭니다.** RDS PostgreSQL 은 pgvector 를 기본으로 담고 있어 파라미터 그룹을 바꿀 필요가 없습니다. incident DB 의 소유자 `incident_app` 은 `rds_superuser` 가 아니라서, `terraform/sql/ops-db-roles.sql` 이 마스터 사용자로 incident DB 에 `CREATE EXTENSION IF NOT EXISTS vector` 를 실행합니다. OPS 마이그레이션은 확장이 있다고 보고 테이블만 만듭니다.

**ExternalDNS 는 `policy=sync` 입니다.** 기본값 `upsert-only` 는 Service 를 지워도 레코드를 남깁니다. `eks.sh down` 은 Service 를 지운 뒤 ExternalDNS 소유 TXT 레코드가 영역에서 사라질 때까지 기다리고 나서 30-platform 을 지웁니다.

**NLB 경보는 미리 만들 수 없습니다.** NLB 는 Traefik Service 를 보고 LB Controller 가 매일 새로 만들어서, 이름과 ARN 을 Terraform 이 모릅니다. NLB 지표 경보가 필요하면 Prometheus 규칙이나 Alertmanager 로 겁니다.

## Prometheus 데이터 볼륨

클러스터를 매일 지워도 Prometheus 지표가 남도록, 10-base 가 상시 EBS 볼륨 하나를 만듭니다. gp3, 암호화, 기본 20GiB 이고 platform 노드와 같은 2c 에 둡니다(변수 `prometheus_volume`). 20GiB 기준 월 약 2달러(추정)입니다. `az` 는 20-eks `node_groups.platform.az` 와 같아야 합니다. 두 층의 mock 테스트가 같은 값(2c)을 검사해서 한쪽만 바꾸면 테스트가 실패합니다.

볼륨을 Prometheus 에 붙이는 정적 PV 와 PVC 는 gitops 에서 만듭니다. `volumeHandle` 에는 10-base output `prometheus_volume.id` 를 넣습니다.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: prometheus-data
spec:
  capacity:
    storage: 20Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: <prometheus_volume.id>
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: [ap-northeast-2c]
```

kube-prometheus-stack values 에서는 PVC 가 이 PV 만 잡도록 이름을 지정합니다.

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ""
          volumeName: prometheus-data
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 20Gi
```

`eks.sh down` 은 PVC 를 모두 지우지만 Retain PV 는 지워지지 않고 Released 로 남으므로 기다리지 않습니다. reclaimPolicy 가 Delete 인 PV 만 지워질 때까지 기다립니다. 볼륨은 10-base 에 있어 태그가 `Layer=base` 이고, `kubernetes.io/cluster/<이름>` 태그도 없어서 `eks.sh leftovers` 가 잔여물로 잡지 않습니다. EBS CSI 정책은 `ebs.csi.aws.com/cluster` 태그가 있는 볼륨만 지울 수 있는데 이 볼륨에는 그 태그를 달지 않습니다.

삭제 주의. EBS 볼륨에는 RDS 의 삭제 방지 같은 설정이 없습니다. `prometheus_volume.az` 를 바꾸면 볼륨을 새로 만들고, 10-base 를 destroy 하면 볼륨이 지워집니다. 둘 다 plan 에서 `aws_ebs_volume.prometheus` 가 destroy 나 replace 로 보이니 apply 전에 확인합니다. RDS 처럼 지울 때 마지막 스냅샷을 남깁니다(`final_snapshot = true`). 크기를 늘리는 것은 볼륨을 다시 만들지 않습니다.

## ops DB 역할 만들기

RDS 는 service, ops 두 대입니다. OPS 의 incident, security 는 ops 인스턴스 안의 DB 두 개이고, 소유자는 로그인 역할 `incident_app`, `security_app` 입니다. 두 역할은 비밀번호가 없고 IAM DB 인증으로만 접속합니다. `incident/ops` 는 `incident_app`, `incident/ops-security-ingest` 는 `security_app` 에만 `rds-db:connect` 가 있습니다. 서로의 DB 에는 CONNECT 권한도 없습니다.

DB 와 역할은 Terraform 이 아니라 `terraform/sql/ops-db-roles.sql` 이 만듭니다. ops 를 처음 만든 뒤 마스터 사용자로 한 번 실행합니다. 다시 실행해도 같은 상태가 됩니다. DB 서브넷은 밖으로 나가는 경로가 없어서 클러스터가 떠 있는 코어타임에 platform 노드의 일회용 psql Pod 로 실행합니다. 마스터 비밀번호는 RDS 가 관리하는 비밀에서 읽어 stdin 으로 넘겨 Pod 스펙에 남기지 않습니다.

```sh
dbs="$(terraform -chdir=terraform/envs/dev/10-base output -json databases)"
{
  aws secretsmanager get-secret-value --secret-id "$(jq -r .ops.master_secret_arn <<<"$dbs")" --query SecretString --output text | jq -r .password
  cat terraform/sql/ops-db-roles.sql
} | kubectl run ops-db-roles --rm -i --restart=Never --image=postgres:17 \
  --overrides='{"apiVersion":"v1","spec":{"nodeSelector":{"role":"platform"},"tolerations":[{"key":"role","operator":"Equal","value":"platform","effect":"NoSchedule"}]}}' \
  --env PGHOST="$(jq -r .ops.address <<<"$dbs")" --env PGUSER=maemusae --env PGDATABASE=ops --env PGSSLMODE=require \
  -- sh -c 'read -r PGPASSWORD && export PGPASSWORD && exec psql'
```

OPS 앱은 접속할 때마다 IAM 인증 토큰을 새로 만들어 비밀번호 자리에 넣습니다. 토큰은 15분만 유효해서 커넥션 풀의 새 연결마다 만듭니다. 연결은 `sslmode=require` 여야 합니다.

```python
token = boto3.client("rds").generate_db_auth_token(DBHostname=host, Port=5432, DBUsername="incident_app")
psycopg.connect(host=host, dbname="incident", user="incident_app", password=token, sslmode="require")
```

## 자원 정리 문서와 다른 점

| 문서 | 이 레포 | 이유 |
| --- | --- | --- |
| §1, §2.1 NAT Gateway 상시 | NAT Gateway 는 20-eks(코어타임), EIP 만 상시 | 노드가 없을 때 NAT 를 쓸 곳이 없다. 운영 결정 표 참고 |
| §2.1 private 라우팅 테이블에 `0.0.0.0/0 → NAT` | 10-base 의 테이블에는 기본 경로가 없고 20-eks 가 `aws_route` 로 더하고 지운다 | NAT 와 수명을 맞춘다 |
| §3.3 코어타임 09:30-18:00 | 평일 13:40-17:30 KST | 운영 결정 표 참고 |
| §4.3 approvals 에 Argo CD 롤백 권한 필요 | Argo CD 권한을 주지 않는다. approvals 는 INFRA 레포에 revert PR 을 열고 merge 해서 되돌린다 | Git 이 배포 기록의 원본으로 남는다. IAM 이나 Argo CD RBAC 설정이 필요 없다 |
| §6 ECR 이미지 FE, BE, webhook, worker, approvals, migrate | `web`, `api`, `migrate`(SERVICE 가 push), `ops`(OPS 가 push) 4개 | OPS 는 이미지 하나에 진입점 api, worker, approvals 를 둔다. 운영 결정 표 참고 |
| §6 Secrets Manager 에 OpenAI 키, Discord 웹훅, DB 접속 정보 | `maemusae/openai`, `maemusae/discord`(봇 토큰), `maemusae/github-rollback-app`(롤백 App private key)와 RDS 마스터 비밀 | 승인 봇에는 웹훅 대신 봇 토큰을 둔다. 웹훅은 경보 채널용 `maemusae/discord-alerts-webhook` 하나만 둔다. 롤백 App 은 approvals 가 INFRA 에 PR 을 열고 merge 할 때 쓴다 |
| 문서에 없음 | private 버킷의 `security-scans/`, 저장소별 스캔 업로드 역할, `ops-security-ingest` Pod Identity | 위 "보안 스캔 업로드" |
| §6 CloudWatch NLB 지표 | RDS 경보만 만든다 | 위 "NLB 경보는 미리 만들 수 없습니다" |
| §6 CloudWatch 로그 그룹 | Discord 경보 Lambda 의 로그 그룹 하나(14일)만 만든다 | 앱과 플랫폼 로그는 Loki 로 간다. 컨트롤 플레인 로그는 매일 지우는 클러스터라 끈다 |
| §5.1 RDS x3 (security, incident, service) | RDS 2개. service 는 상시, ops 는 코어타임에만 켜고 그 안에 incident, security DB 를 둔다 | 운영 결정 표의 RDS 대수 참고 |
| §5.2 S3 uploads, loki 와 CloudTrail 버킷 | S3 2개. public 과, 접두사(`uploads/`, `loki/`, `cloudtrail/`, `security-scans/`)로 나눈 private | 위 "S3 버킷" |
| 문서에 없음 | DB 전용 서브넷 2a, 2c 와 기본 경로 없는 라우팅 테이블 | 위 "RDS 는 DB 전용 서브넷에 있습니다" |
| 문서에 없음 | RDS 이벤트 구독 | 운영 결정 표 참고 |
| 문서에 없음 | Prometheus 데이터용 상시 EBS 볼륨 | 위 "Prometheus 데이터 볼륨" |
| §8 `pod-identity` 모듈이 역할과 연결을 함께 만든다 | 모듈은 역할만, 연결은 20-eks root | 위 "Pod Identity 역할은 10-base 에" |
| §8 `rds` 모듈을 3번 호출 | `module "rds"` 하나를 `for_each = var.databases` 로 2번 | DB 를 더하고 빼는 일이 변수 한 줄이다 |
| §8 10-base 에 network 모듈 | network 모듈이 노드 보안 그룹과 RDS 보안 그룹도 만든다 | §2.3 이 네트워크 절에 있고, 두 그룹 모두 상시여야 한다 |

## Argo CD 와 애드온 설치

30-platform 은 LB Controller, External Secrets, Argo CD 를, 영역 ID 가 있으면 ExternalDNS 도 Helm 으로 설치합니다. LB Controller 웹훅이 Service 생성을 가로채서, 나머지 차트는 LB Controller 가 뜬 뒤 설치합니다. 루트 앱은 `gitops/` 가 생긴 뒤에 더합니다. kube-prometheus-stack, Loki, Alloy, Traefik, kube-bench, 앱은 Argo CD 가 `gitops/` 에서 설치합니다.

## 운영 결정 (2026-11-25)

| 항목 | 결정 | 다시 볼 때 |
| --- | --- | --- |
| 가용 영역 | 퍼블릭 서브넷, NAT, app 노드 모두 2a 하나. 비용 절감을 위해 2a 장애 시 서비스와 egress 가 같이 끊기는 것을 받아들인다 | 운영 트래픽을 받을 때 퍼블릭 서브넷과 NAT 를 2c 에도 두고 app 노드를 2c 에도 둔다. `modules/network` 의 퍼블릭 서브넷을 map 으로 바꿔야 한다 |
| NAT | NAT Gateway 는 코어타임에만, EIP 는 상시. 서울 단가(Pricing API 조회값)는 NAT $0.059/h, 공인 IPv4 $0.005/h 다. 상시면 월 약 $46.7, 코어타임 NAT(평일 22일 x 4시간) + 상시 EIP 면 월 약 $8.8 이다. 데이터 처리 요금은 뺀 값이다. 출구 IP 는 EIP 가 붙잡고 있어 매일 같다. NAT 를 상시로 둔 사례(nerd-nam)는 EKS 와 NLB 를 남기는 구조였고, 여기는 EKS 를 매일 지워서 해당하지 않는다 | 코어타임 밖에 노드나 다른 private 리소스가 외부로 나가야 하면 NAT 를 10-base 로 옮긴다 |
| 코어타임 | 평일 13:40-17:30 KST. EKS 생성에 15분 안팎이 걸려 14:00 부터 쓸 수 있게 일찍 올린다. 정리 cron 이 30분마다 돌아 17:35 전후에 내려간다 | 팀 일정이 바뀌면 `eks.sh` 의 `UP_AT`, `CORE_END` 와 `eks.yml` 의 올리기 cron, Decide action 의 비교 문자열을 함께 바꾼다 |
| 도메인 | 아직 없음. `route53_zone_id`, `ses_domain` 이 비어 있어 ExternalDNS 역할과 설치, SES 도메인, DKIM 레코드를 만들지 않는다 | 도메인을 산 뒤 두 변수를 채운다 |
| CloudTrail | 2026-11-25 에 계정에서 `describe-trails --include-shadow-trails`(ap-northeast-2)로 확인한 결과 trail 이 없다. 이 trail 이 첫 trail 이라 관리 이벤트 사본 과금이 없다 | 다른 팀이 trail 을 만들면 하나로 합친다 |
| apply 역할 권한 | PowerUser 와 IAMFull 을 유지한다 | INFRA issue #2 에서 보안팀과 합의해 줄인다 |
| approvals 롤백 | Argo CD 롤백이 아니라 INFRA PR merge 로 되돌린다. GitHub App 을 둘로 나눈다. image-PR App 은 CI 가 이미지 태그 PR 을 열 때, 롤백 App 은 클러스터 안 approvals 봇이 쓴다. Discord 승인이 PR 리뷰를 대신하므로 롤백 App 만 `main` ruleset 우회 목록에 넣는다. 설치 범위, 권한, 키 보관은 README 의 GitHub 설정 체크리스트대로 한다. App 과 ruleset 은 아직 만들지 않았다 | 우회 범위를 넓히거나 다른 주체를 우회 목록에 넣을 때. 보안팀 리뷰를 거친다 |
| 승인 역할 | Discord 승인자는 처음에 풀스택, 인프라, 보안팀 역할이다. 역할 ID 는 비밀이 아니라 OPS 설정이고, `maemusae/discord` 에는 봇 토큰만 둔다 | 승인자를 좁힐 때 OPS 설정만 바꾼다 |
| ECR 저장소 | `web`, `api`, `migrate` 는 SERVICE, `ops` 는 OPS 가 push 한다. OPS 는 이미지 하나에 진입점 api, worker, approvals 를 둔다 | OPS 가 이미지를 나누면 `ecr_repositories` 에 줄을 더한다 |
| 보안 스캔 결과 | S3 `maemusae-private-<계정 ID>` 의 `security-scans/` 에 올리고 90일 보관한다. 키 형식과 역할은 위 "보안 스캔 업로드" | 보관 기간이나 올리는 저장소가 바뀔 때 |
| Redis | ElastiCache 가 아니라 클러스터 안 StatefulSet. Terraform 에 없다. 클러스터를 매일 지우므로 장애 큐 데이터가 그때 사라지는 것을 받아들인다 | 큐 데이터를 하루 넘게 보존해야 할 때 ElastiCache 나 10-base 의 영속 저장소를 검토한다 |
| DB 서브넷 | RDS 는 DB 전용 서브넷 2a, 2c 에 둔다. 라우팅 테이블에 기본 경로가 없어 NAT 나 IGW 로 나갈 수 없다. 노드 서브넷과 RDS 보안 그룹(노드에서 오는 5432)은 그대로다 | RDS 가 외부(예: S3 내보내기)에 닿아야 할 때 VPC endpoint 를 DB 라우팅 테이블에 더한다 |
| RDS AZ | RDS 2개를 2a 에 둔다(`rds_availability_zone`). app 노드와 같은 AZ 라 AZ 간 지연과 전송 요금이 없다. 서브넷 그룹은 2a, 2c 를 유지하고 Multi-AZ 는 끈다 | 운영 트래픽을 받거나 2a 장애를 견뎌야 할 때 service DB 부터 Multi-AZ 를 켠다 |
| RDS 이벤트 | DB 2개의 availability, failover, failure, low storage, maintenance, notification, recovery 이벤트를 CloudWatch 경보와 같은 alerts 주제로 보낸다. 같은 계정 RDS 는 주제 기본 정책으로 게시할 수 있어 주제 정책을 두지 않는다 | 주제를 암호화하거나 다른 계정 RDS 를 받을 때 주제 정책을 더한다 |
| 경보 알림 | alerts 주제를 메일과 Discord 로 함께 받는다. Lambda(Python 3.13, arm64)가 RDS 이벤트와 CloudWatch 경보를 한 줄 요약으로 바꿔 웹훅에 보낸다. 웹훅 URL 은 `maemusae/discord-alerts-webhook` 에 두고 실행 중에 읽는다. 매일 ops 를 끄고 켜는 RDS-EVENT-0087(정지), RDS-EVENT-0088(시작)은 Discord 로 보내지 않고, 정지 7일을 넘겨 스스로 켜진 RDS-EVENT-0154 는 보낸다 | 메일도 매일 정지, 시작 이벤트를 받는다. 시끄러우면 메일 구독에 필터 정책을 더한다 |
| RDS 대수 | service, ops 2개. OPS 의 incident, security 는 ops 안의 DB 두 개다. ops 는 `eks.sh` 가 코어타임에만 켠다. 서울 단가 db.t4g.micro $0.025/h, gp3 $0.131/GB-월 기준 20GB 면 상시 월 약 $20.9, 코어타임(평일 22일 x 4시간)이면 월 약 $4.8 이다. 정지 중에도 저장 공간 요금은 나간다. service 는 SERVICE 앱이 늘 쓰므로 상시다 | OPS 가 코어타임 밖에도 DB 를 써야 하면 `eks.sh` 의 ops 정지를 뺀다 |
| ops DB 인증 | `incident_app`, `security_app` 은 비밀번호 없이 IAM DB 인증으로만 접속한다. Pod Identity 역할마다 자기 DB 사용자 하나에만 `rds-db:connect` 가 있다. 역할과 DB 는 `terraform/sql/ops-db-roles.sql` 로 만든다 | 다른 앱이 ops 에 붙을 때 역할과 정책을 같은 방식으로 더한다 |
| S3 | public, private 2개. 공개 업로드는 public, 나머지는 private 의 접두사로 나눈다. 위 "S3 버킷" | 접두사마다 다른 암호화 키나 복제가 필요해지면 버킷을 나눈다 |
| 노드 접속 | SSH 키와 22 포트 없이 SSM Session Manager 로만 들어간다. 노드 역할에 `AmazonSSMManagedInstanceCore` 를 붙였다 | - |
| Prometheus 데이터 | 10-base 의 상시 EBS(2c, 20GiB)에 남겨 날짜를 넘어 지표를 비교한다. Alertmanager silence 와 Grafana 에서 손으로 고친 내용은 여전히 매일 사라진다. 대시보드는 gitops 코드로 관리한다 | 보존 기간이 늘어 20GiB 가 모자라면 `prometheus_volume.size_gib` 를 늘린다 |
| incident 배치 (보류) | 첫 클러스터를 올린 뒤 platform 노드의 메모리 여유를 잰다. 여유가 있으면 `incident` namespace 를 platform 노드(2c)로 옮겨 app 노드가 죽어도 장애 대응 봇이 살아 있게 한다. NAT 가 2a 에 있어 2a 전체 장애에는 도움이 되지 않는다. Terraform 변경은 없다 | 첫 클러스터 기동 뒤 측정값으로 정한다 |
