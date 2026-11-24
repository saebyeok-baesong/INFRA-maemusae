variable "aws_account_id" {
  description = "적용할 AWS 계정 ID. 공개 저장소라 파일에 두지 않고 TF_VAR_aws_account_id 로 넘긴다"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id 는 12자리 숫자여야 한다."
  }
}

variable "region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "name" {
  description = "VPC, 클러스터, 리소스 이름 접두사"
  type        = string
  default     = "maemusae"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.50.0.0/16"
}

variable "azs" {
  description = "프라이빗 서브넷 AZ. 순서대로 private_subnet_cidrs 와 짝을 이룬다. EKS 와 RDS 서브넷 그룹이 AZ 2개를 요구한다"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "private_subnet_cidrs" {
  description = "AZ 별 프라이빗 서브넷 (노드, RDS)"
  type        = list(string)
  default     = ["10.50.0.0/20", "10.50.16.0/20"]
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 (NAT, NLB). azs 앞에서부터 짝을 이룬다. 기본은 2a 하나"
  type        = list(string)
  default     = ["10.50.200.0/24"]
}

variable "ecr_repositories" {
  description = "ECR 저장소 이름 => 그 저장소에 push 할 GitHub 저장소 (owner/repo)"
  type        = map(string)
  default = {
    web = "saebyeok-baesong/SERVICE-maemusae"
    api = "saebyeok-baesong/SERVICE-maemusae"
    ops = "saebyeok-baesong/OPS-maemusae"
  }
}

variable "ecr_push_ref" {
  description = "ECR push 역할을 assume 할 수 있는 git ref"
  type        = string
  default     = "refs/heads/main"
}

variable "databases" {
  description = "RDS PostgreSQL 인스턴스. 키가 식별자와 DB 이름이 된다"
  type = map(object({
    instance_class    = optional(string, "db.t4g.micro")
    allocated_storage = optional(number, 20)
    engine_version    = optional(string, "17")
  }))
  default = {
    security = {}
    incident = {}
    service  = {}
  }
}

variable "rds_deletion_protection" {
  description = "RDS 삭제 방지. 프로젝트를 정리할 때만 false 로 바꿔 apply 한 뒤 destroy 한다"
  type        = bool
  default     = true
}

variable "rds_backup_retention_days" {
  description = "RDS 자동 백업 보존 기간(일)"
  type        = number
  default     = 7
}

variable "app_secret_names" {
  description = "Secrets Manager 비밀 이름. 값은 사람이 CLI 로 넣고 External Secrets 가 클러스터로 옮긴다"
  type        = list(string)
  default     = ["maemusae/service", "maemusae/ops"]
}

variable "loki_retention_days" {
  description = "Loki 버킷 객체 보존 기간(일)"
  type        = number
  default     = 14
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail 버킷 객체 보존 기간(일)"
  type        = number
  default     = 365
}

variable "budget_limit_usd" {
  description = "월 예산(USD)"
  type        = number
  default     = 100
}

variable "budget_email" {
  description = "예산 알림 메일 주소. 공개 저장소라 TF_VAR_budget_email 로 넘긴다"
  type        = string
}

variable "ses_domain" {
  description = "보고서 메일을 보낼 SES 도메인. 비우면 만들지 않는다"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "ExternalDNS 가 레코드를 쓸 Route53 호스팅 영역 ID. 비우면 ExternalDNS 역할을 만들지 않는다"
  type        = string
  default     = ""
}
