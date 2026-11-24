locals {
  # expire_days = null 이면 객체를 지우지 않는다
  buckets = {
    uploads    = { force_destroy = false, expire_days = null }
    loki       = { force_destroy = true, expire_days = var.loki_retention_days }
    cloudtrail = { force_destroy = false, expire_days = var.cloudtrail_retention_days }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.name}-${each.key}-${var.aws_account_id}"
  force_destroy = each.value.force_destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = { for k, v in local.buckets : k => v if v.expire_days != null }

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    id     = "expire"
    status = "Enabled"
    filter {}

    expiration {
      days = each.value.expire_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_ecr_repository" "this" {
  for_each = var.ecr_repositories

  name = each.key
  # 배포는 digest 로 고정하지만, 같은 태그 재푸시로 다른 이미지가 올라가는 것도 막는다
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 50 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 50 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_secretsmanager_secret" "app" {
  for_each = toset(var.app_secret_names)

  name = each.key
}
