provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  # eks.sh leftovers 가 Layer=eks 태그로 남은 리소스를 찾는다
  default_tags {
    tags = local.tags
  }
}
