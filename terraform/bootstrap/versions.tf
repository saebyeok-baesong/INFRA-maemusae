terraform {
  required_version = ">= 1.11.1, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # state 버킷 자체를 만드는 층이라 로컬 state 로 시작한다. 이전 절차는 README 에 있다.
}
