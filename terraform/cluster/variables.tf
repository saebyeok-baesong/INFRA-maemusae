variable "aws_account_id" {
  description = "적용할 AWS 계정 ID. 공개 저장소라 파일에 두지 않고 TF_VAR_aws_account_id 로 넘긴다"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket_prefix" {
  description = "bootstrap 의 project 값. base state 버킷 이름은 <prefix>-tfstate-<계정 ID>"
  type        = string
  default     = "maemusae"
}

variable "kubernetes_version" {
  description = "EKS 버전. 표준 지원 기간 안의 버전만 쓴다 (1.35 표준 지원 종료 2027-03-27)"
  type        = string
  default     = "1.35"
}

variable "node_groups" {
  description = "노드그룹 이름 => AZ 와 인스턴스. 이름이 노드 라벨과 taint role=<이름> 이 된다. 이미지가 arm64 라 Graviton 이어야 한다"
  type = map(object({
    az            = string
    instance_type = optional(string, "t4g.large")
    size          = optional(number, 1)
  }))
  default = {
    app      = { az = "ap-northeast-2a" }
    platform = { az = "ap-northeast-2c" }
  }
}

variable "endpoint_allowed_cidrs" {
  description = "컨트롤 플레인 공개 엔드포인트에 늘 허용할 CIDR (운영자 고정 IP 등)"
  type        = list(string)
  default     = []
}

variable "caller_cidr" {
  description = "apply 하는 곳의 IP/32. eks.sh 가 넘긴다. Argo CD helm 설치가 이 IP 에서 API 를 부른다"
  type        = string
}

variable "admin_principal_arns" {
  description = "클러스터 관리자 IAM 주체 (운영자, GitHub Actions apply 역할). apply 하는 주체는 자동으로 관리자가 된다. TF_VAR_admin_principal_arns 로 넘긴다"
  type        = list(string)
  default     = []
}

variable "argocd_chart_version" {
  description = "argo-cd Helm 차트 버전"
  type        = string
  default     = "10.17.2"
}
