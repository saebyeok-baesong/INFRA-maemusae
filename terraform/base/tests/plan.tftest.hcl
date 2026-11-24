# AWS 에 접속하지 않는 plan. terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  aws_account_id = "123456789012"
  budget_email   = "ops@example.com"
}

run "default_draft" {
  command = plan

  assert {
    condition     = length(aws_db_instance.this) == 3
    error_message = "security, incident, service DB 3개"
  }

  assert {
    condition     = keys(aws_iam_role.ecr_push) == ["saebyeok-baesong/OPS-maemusae", "saebyeok-baesong/SERVICE-maemusae"]
    error_message = "ECR push 역할은 GitHub 저장소마다 하나"
  }

  assert {
    condition     = !contains(keys(local.workload_identities), "external-dns")
    error_message = "Route53 영역이 없으면 ExternalDNS 역할을 만들지 않는다"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.report) == 0
    error_message = "ses_domain 이 비면 SES 를 만들지 않는다"
  }

  assert {
    condition     = keys(aws_s3_bucket_lifecycle_configuration.this) == ["cloudtrail", "loki"]
    error_message = "uploads 버킷은 만료 규칙이 없다"
  }
}

run "with_domain" {
  command = plan

  variables {
    route53_zone_id = "Z0000000000000"
    ses_domain      = "example.com"
  }

  assert {
    condition     = contains(keys(local.workload_identities), "external-dns")
    error_message = "Route53 영역이 있으면 ExternalDNS 역할을 만든다"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.report) == 1
    error_message = "ses_domain 이 있으면 SES 도메인을 만든다"
  }
}
