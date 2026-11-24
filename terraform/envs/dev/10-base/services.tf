resource "aws_ecr_repository" "this" {
  for_each = var.ecr_repositories

  name = each.key
  # 같은 태그를 다시 push 해서 다른 이미지가 올라가는 것을 막는다
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
      description  = "keep last ${var.ecr_keep_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.ecr_keep_images }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_secretsmanager_secret" "app" {
  for_each = toset(var.app_secrets)

  name = "${var.name}/${each.key}"
}

resource "aws_sesv2_email_identity" "report" {
  count = var.ses_domain == "" ? 0 : 1

  email_identity = var.ses_domain

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

# Easy DKIM 은 토큰을 늘 3개 준다
resource "aws_route53_record" "ses_dkim" {
  count = var.ses_domain != "" && var.route53_zone_id != "" ? 3 : 0

  zone_id = var.route53_zone_id
  name    = "${aws_sesv2_email_identity.report[0].dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.ses_domain}"
  type    = "CNAME"
  ttl     = 1800
  records = ["${aws_sesv2_email_identity.report[0].dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# 메일로 온 확인 링크를 눌러야 구독이 시작된다
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  # 버킷 정책이 트레일 ARN 을 조건에 쓰고 트레일은 버킷 정책이 있어야 만들어져서, ARN 을 이름으로 미리 짓는다
  trail_arn = "arn:aws:cloudtrail:${var.region}:${var.aws_account_id}:trail/${var.name}"
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.this["cloudtrail"].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this["cloudtrail"].arn}/AWSLogs/${var.aws_account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.this["cloudtrail"].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "this" {
  name                          = var.name
  s3_bucket_name                = aws_s3_bucket.this["cloudtrail"].id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"

  cost_types {
    include_credit   = false
    include_discount = false
    include_refund   = false
  }

  dynamic "notification" {
    for_each = toset([50, 70, 100])
    content {
      notification_type          = "ACTUAL"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      comparison_operator        = "GREATER_THAN"
      subscriber_email_addresses = [var.alert_email]
    }
  }
}
