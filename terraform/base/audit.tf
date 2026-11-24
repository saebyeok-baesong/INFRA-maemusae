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

locals {
  # 버킷 정책이 트레일 ARN 을 조건에 쓰고 트레일은 버킷 정책이 있어야 만들어져서, ARN 을 이름으로 미리 짓는다
  trail_arn = "arn:aws:cloudtrail:${var.region}:${var.aws_account_id}:trail/${var.name}"
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
      subscriber_email_addresses = [var.budget_email]
    }
  }
}

resource "aws_sesv2_email_identity" "report" {
  count = var.ses_domain == "" ? 0 : 1

  email_identity = var.ses_domain
}
