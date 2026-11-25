# INFRA-maemusae

매무새 EKS 환경의 인프라와 배포 정의입니다. Argo CD는 이 레포의 `gitops/`만 바라봅니다.

| 경로 | 내용 | 담당 |
| --- | --- | --- |
| `terraform/` | VPC, EKS, RDS, ECR, IAM 역할 | infra |
| `gitops/` | Argo CD app-of-apps, 앱과 관측 스택 values | infra |
| `gitops/security/` | 보안 정책, kube-bench, NetworkPolicy | security |
| `iam/` | IAM 정책 문서 | security, infra |

앱 이미지는 앱 레포 CI가 이 레포에 PR을 열어 올립니다. 결정 배경은 [SPEC adr/0001](https://github.com/saebyeok-baesong/SPEC-maemusae/blob/main/adr/0001-repo-structure.md)을 보세요.
