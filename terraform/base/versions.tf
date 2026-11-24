terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # bucket 은 계정 ID 가 들어가 공개 저장소에 두지 않는다. README 의 init 명령으로 넘긴다
  backend "s3" {}
}
