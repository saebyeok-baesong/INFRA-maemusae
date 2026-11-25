variable "aws_account_id" {
  description = "적용할 AWS 계정 ID. state 버킷 이름에 들어간다. TF_VAR_aws_account_id 로 넘긴다"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id 는 12자리 숫자여야 한다."
  }
}

variable "region" {
  description = "state 버킷 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket_prefix" {
  description = "bootstrap 의 project 값. state 버킷 이름은 <prefix>-tfstate-<계정 ID>"
  type        = string
  default     = "maemusae"
}

variable "chart_versions" {
  description = "Helm 차트 버전. LB Controller 를 올리면 iam/policies/aws-load-balancer-controller.json 도 같은 버전의 정책으로 바꾼다"
  type = object({
    aws_load_balancer_controller = optional(string, "3.6.3")
    external_secrets             = optional(string, "2.15.0")
    external_dns                 = optional(string, "1.23.0")
    argocd                       = optional(string, "10.17.2")
    argocd_apps                  = optional(string, "2.0.2")
  })
  default = {}
}

variable "gitops_repo_url" {
  description = "Argo CD root 앱이 gitops/apps/ 를 읽을 저장소 (public)"
  type        = string
  default     = "https://github.com/saebyeok-baesong/INFRA-watch-nyang.git"
}
