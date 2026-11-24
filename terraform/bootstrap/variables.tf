variable "aws_account_id" {
  description = "적용할 AWS 계정 ID. 공개 저장소라 파일에 두지 않고 TF_VAR_aws_account_id 로 넘긴다"
  type        = string
}

variable "project" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "maemusae"
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_repository" {
  description = "plan/apply 역할을 믿을 저장소 (owner/repo)"
  type        = string
  default     = "saebyeok-baesong/INFRA-maemusae"
}

variable "github_environments" {
  description = "apply 역할을 assume 할 수 있는 GitHub Environment. production 은 승인 규칙을, eks 는 main 브랜치 제한만 건다 (스케줄이 승인을 기다리지 않게)"
  type        = list(string)
  default     = ["production", "eks"]
}

variable "create_github_oidc_provider" {
  description = "계정에 GitHub OIDC 공급자가 아직 없으면 true"
  type        = bool
  default     = true
}

variable "apply_role_policy_arns" {
  description = "apply 역할에 붙일 정책 ARN. 보안팀과 협의해 최소 권한으로 줄인다"
  type        = map(string)
  default = {
    power_user = "arn:aws:iam::aws:policy/PowerUserAccess"
    iam_full   = "arn:aws:iam::aws:policy/IAMFullAccess"
  }
}
