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

variable "public_subnet" {
  description = "퍼블릭 서브넷 (NAT, NLB)"
  type = object({
    az   = string
    cidr = string
  })
  default = { az = "ap-northeast-2a", cidr = "10.50.200.0/24" }
}

variable "private_subnets" {
  description = "AZ => 프라이빗 서브넷 CIDR (노드)"
  type        = map(string)
  default = {
    "ap-northeast-2a" = "10.50.0.0/20"
    "ap-northeast-2c" = "10.50.16.0/20"
  }
}

variable "db_subnets" {
  description = "AZ => DB 서브넷 CIDR (RDS). 기본 경로가 없는 라우팅 테이블을 쓴다"
  type        = map(string)
  default = {
    "ap-northeast-2a" = "10.50.100.0/24"
    "ap-northeast-2c" = "10.50.101.0/24"
  }
}

variable "rds_availability_zone" {
  description = "RDS 를 둘 AZ. app 노드와 같은 AZ 에 둬 AZ 간 전송 요금을 없앤다"
  type        = string
  default     = "ap-northeast-2a"

  validation {
    condition     = contains(keys(var.db_subnets), var.rds_availability_zone)
    error_message = "rds_availability_zone 은 db_subnets 의 AZ 중 하나여야 한다."
  }
}

variable "databases" {
  description = "RDS PostgreSQL 인스턴스. 키가 식별자 접미사와 DB 이름이 된다. ops 안의 incident, security DB 는 terraform/sql/ops-db-roles.sql 이 만든다"
  type = map(object({
    instance_class    = optional(string, "db.t4g.micro")
    allocated_storage = optional(number, 20)
    engine_version    = optional(string, "17")
  }))
  default = {
    service = {}
    ops     = {}
  }

  validation {
    condition     = contains(keys(var.databases), "ops")
    error_message = "ops 는 빼지 않는다. OPS Pod Identity 의 rds-db:connect 정책이 ops 인스턴스를 가리킨다."
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

variable "rds_alarm_thresholds" {
  description = "RDS CloudWatch 경보 기준. db.t4g.micro 의 max_connections 는 100 남짓이다"
  type = object({
    cpu_percent      = number
    free_storage_gib = number
    connections      = number
  })
  default = {
    cpu_percent      = 80
    free_storage_gib = 2
    connections      = 80
  }
}

variable "prometheus_volume" {
  description = "Prometheus 데이터용 상시 EBS. az 는 20-eks node_groups.platform.az 와 같아야 한다"
  type = object({
    az       = string
    size_gib = number
  })
  default = { az = "ap-northeast-2c", size_gib = 20 }

  validation {
    condition     = contains(keys(var.private_subnets), var.prometheus_volume.az)
    error_message = "prometheus_volume.az 는 노드 서브넷(private_subnets)의 AZ 중 하나여야 한다."
  }
}

variable "ecr_repositories" {
  description = "ECR 저장소 이름 => 그 저장소에 push 할 GitHub 저장소 (owner/repo). 줄을 지우면 저장소와 push 권한이 같이 빠진다"
  type        = map(string)
  default = {
    web     = "saebyeok-baesong/SERVICE-watch-nyang"
    api     = "saebyeok-baesong/SERVICE-watch-nyang"
    migrate = "saebyeok-baesong/SERVICE-watch-nyang"
    ops     = "saebyeok-baesong/OPS-watch-nyang"
  }
}

variable "ecr_keep_images" {
  description = "ECR 저장소마다 남길 최근 이미지 수"
  type        = number
  default     = 30
}

variable "ecr_push_ref" {
  description = "ECR push 역할을 assume 할 수 있는 git ref"
  type        = string
  default     = "refs/heads/main"
}

variable "app_secrets" {
  description = "Secrets Manager 비밀. <name>/<항목> 이름으로 만든다. 값은 사람이 CLI 로 넣고 External Secrets 가 클러스터로 옮긴다"
  type        = list(string)
  default     = ["openai", "discord", "github-rollback-app", "discord-alerts-webhook"]
}

variable "security_scan_repositories" {
  description = "보안 스캔 결과를 private 버킷의 security-scans/<저장소 이름>/ 아래에 올릴 GitHub 저장소 (owner/repo)"
  type        = list(string)
  default = [
    "saebyeok-baesong/SERVICE-watch-nyang",
    "saebyeok-baesong/OPS-watch-nyang",
    "saebyeok-baesong/INFRA-watch-nyang",
  ]
}

variable "security_scan_retention_days" {
  description = "private 버킷 security-scans/ 객체 보존 기간(일)"
  type        = number
  default     = 90
}

variable "loki_retention_days" {
  description = "private 버킷 loki/ 객체 보존 기간(일)"
  type        = number
  default     = 14
}

variable "cloudtrail_retention_days" {
  description = "private 버킷 cloudtrail/ 객체 보존 기간(일)"
  type        = number
  default     = 365
}

variable "budget_limit_usd" {
  description = "월 예산(USD)"
  type        = number
  default     = 100
}

variable "alert_email" {
  description = "예산 알림과 RDS 경보를 받을 메일 주소. 공개 저장소라 TF_VAR_alert_email 로 넘긴다"
  type        = string
}

variable "ses_domain" {
  description = "보고서 메일을 보낼 SES 도메인. 비우면 만들지 않는다"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "도메인의 Route53 호스팅 영역 ID. 비우면 ExternalDNS 역할과 SES DKIM 레코드를 만들지 않는다"
  type        = string
  default     = ""
}
