locals {
  # base, cluster, eks.sh, CI 가 계정 ID 만으로 같은 이름을 다시 만든다
  state_bucket = "${var.project}-tfstate-${var.aws_account_id}"
}

module "state_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.17.0"

  bucket = local.state_bucket

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }

  lifecycle_rule = [
    {
      id      = "state-history"
      enabled = true
      filter  = {}
      noncurrent_version_expiration = {
        days = 90
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}

module "github_oidc" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.8.2"

  create = var.create_github_oidc_provider
  url    = "https://token.actions.githubusercontent.com"
}

module "state_access_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "6.8.2"

  name        = "${var.project}-tfstate-access"
  description = "Read/write Terraform state and its S3 lock files"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = module.state_bucket.s3_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.state_bucket.s3_bucket_arn}/*"
      },
    ]
  })
}

module "plan_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name = "${var.project}-gha-plan"

  enable_github_oidc = true
  oidc_subjects = [
    "repo:${var.github_repository}:pull_request",
    "repo:${var.github_repository}:ref:refs/heads/*",
  ]

  policies = {
    read_only    = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    state_access = module.state_access_policy.arn
  }

  depends_on = [module.github_oidc]
}

module "apply_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.2"

  name = "${var.project}-gha-apply"

  enable_github_oidc = true
  oidc_subjects      = [for env in var.github_environments : "repo:${var.github_repository}:environment:${env}"]

  policies = merge(var.apply_role_policy_arns, {
    state_access = module.state_access_policy.arn
  })

  depends_on = [module.github_oidc]
}
