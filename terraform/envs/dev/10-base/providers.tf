provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  # eks.sh leftovers 는 Layer=eks 만 센다. 이 층의 리소스는 늘 남아 있어야 한다
  default_tags {
    tags = {
      Project   = var.name
      Layer     = "base"
      ManagedBy = "terraform"
    }
  }
}
