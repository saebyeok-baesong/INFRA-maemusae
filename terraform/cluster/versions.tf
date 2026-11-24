terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # bucket 은 계정 ID 가 들어가 공개 저장소에 두지 않는다. eks.sh 와 README 의 init 명령으로 넘긴다
  backend "s3" {}
}
