variable "identifier" {
  description = "RDS 인스턴스 식별자. 경보 이름 접두사로도 쓴다"
  type        = string
}

variable "db_name" {
  description = "처음 만들 데이터베이스 이름"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL 메이저 버전"
  type        = string
}

variable "instance_class" {
  description = "인스턴스 클래스"
  type        = string
}

variable "allocated_storage" {
  description = "저장 공간(GiB)"
  type        = number
}

variable "subnet_group_name" {
  description = "DB 서브넷 그룹 이름"
  type        = string
}

variable "security_group_ids" {
  description = "인스턴스에 붙일 보안 그룹"
  type        = list(string)
}

variable "backup_retention_days" {
  description = "자동 백업 보존 기간(일)"
  type        = number
}

variable "deletion_protection" {
  description = "삭제 방지"
  type        = bool
}

variable "alarm_topic_arn" {
  description = "경보와 복구 알림을 보낼 SNS 주제"
  type        = string
}

variable "alarm_thresholds" {
  description = "CloudWatch 경보 기준"
  type = object({
    cpu_percent      = number
    free_storage_gib = number
    connections      = number
  })
}
