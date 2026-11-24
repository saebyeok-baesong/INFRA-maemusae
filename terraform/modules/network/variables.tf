variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "region" {
  description = "S3 endpoint 서비스 이름에 쓰는 리전"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "public_subnet" {
  description = "퍼블릭 서브넷 하나 (NAT, NLB). 단일 AZ 를 받아들인 결정은 docs/architecture.md 운영 결정에 있다"
  type = object({
    az   = string
    cidr = string
  })
}

variable "private_subnets" {
  description = "AZ => 프라이빗 서브넷 CIDR (노드). EKS 컨트롤 플레인이 AZ 2개를 요구한다"
  type        = map(string)

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "프라이빗 서브넷은 AZ 2개 이상이어야 한다."
  }
}

variable "db_subnets" {
  description = "AZ => DB 서브넷 CIDR (RDS). RDS 서브넷 그룹이 AZ 2개를 요구한다"
  type        = map(string)

  validation {
    condition     = length(var.db_subnets) >= 2
    error_message = "DB 서브넷은 AZ 2개 이상이어야 한다."
  }
}
