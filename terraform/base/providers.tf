provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  # eks.sh leftovers 는 Project=maemusae 중 Layer=base 를 빼고 센다
  default_tags {
    tags = {
      Project   = var.name
      Layer     = "base"
      ManagedBy = "terraform"
    }
  }
}
