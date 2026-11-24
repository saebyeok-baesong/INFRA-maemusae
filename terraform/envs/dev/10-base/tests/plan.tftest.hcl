# AWS 에 접속하지 않는 plan. terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  aws_account_id = "123456789012"
  alert_email    = "ops@example.com"
}

run "no_domain" {
  command = plan

  assert {
    condition     = keys(module.rds) == ["incident", "security", "service"]
    error_message = "security, incident, service DB 3개"
  }

  assert {
    condition     = alltrue([for db in module.rds : length(db.alarm_names) == 3])
    error_message = "DB 마다 CPU, 저장 공간, 연결 경보"
  }

  assert {
    condition     = keys(aws_ecr_repository.this) == ["api", "migrate", "ops", "web"]
    error_message = "ECR 저장소는 SERVICE 의 web, api, migrate 와 OPS 이미지 하나(ops)"
  }

  assert {
    condition     = keys(aws_ecr_lifecycle_policy.this) == keys(aws_ecr_repository.this)
    error_message = "ECR 저장소마다 수명 주기 정책"
  }

  assert {
    condition     = keys(aws_iam_role.ecr_push) == ["saebyeok-baesong/OPS-maemusae", "saebyeok-baesong/SERVICE-maemusae"]
    error_message = "ECR push 역할은 GitHub 저장소마다 하나"
  }

  assert {
    condition     = keys(module.pod_identity.identities) == ["api", "aws-load-balancer-controller", "ebs-csi", "external-secrets", "loki", "ops-security-ingest"]
    error_message = "Route53 영역이 없으면 ExternalDNS 역할을 만들지 않는다"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.report) == 0 && length(aws_route53_record.ses_dkim) == 0
    error_message = "ses_domain 이 비면 SES 를 만들지 않는다"
  }

  assert {
    condition     = keys(aws_s3_bucket_lifecycle_configuration.this) == ["cloudtrail", "loki", "security-scans"]
    error_message = "uploads 버킷은 만료 규칙이 없다"
  }

  assert {
    condition     = keys(aws_s3_bucket_server_side_encryption_configuration.this) == ["cloudtrail", "loki", "security-scans", "uploads"] && keys(aws_s3_bucket_public_access_block.this) == keys(aws_s3_bucket.this)
    error_message = "모든 버킷에 SSE 와 퍼블릭 차단"
  }

  assert {
    condition     = aws_s3_bucket.this["security-scans"].bucket == "maemusae-security-scans-123456789012" && one(aws_s3_bucket_lifecycle_configuration.this["security-scans"].rule).expiration[0].days == 90
    error_message = "스캔 버킷은 OPS, SPEC 과 맞춘 이름이고 90일 뒤 지운다"
  }

  assert {
    condition     = module.pod_identity.identities["ops-security-ingest"].namespace == "incident" && module.pod_identity.identities["ops-security-ingest"].service_account == "ops-security-ingest"
    error_message = "스캔 수집기는 incident/ops-security-ingest"
  }

  assert {
    condition     = keys(aws_iam_role.scan_upload) == ["saebyeok-baesong/INFRA-maemusae", "saebyeok-baesong/OPS-maemusae", "saebyeok-baesong/SERVICE-maemusae"]
    error_message = "스캔 업로드 역할은 SERVICE, OPS, INFRA 마다 하나"
  }

  assert {
    condition     = aws_secretsmanager_secret.app["openai"].name == "maemusae/openai" && aws_secretsmanager_secret.app["github-rollback-app"].name == "maemusae/github-rollback-app"
    error_message = "앱 비밀과 롤백 App 키는 External Secrets 가 읽는 maemusae/ 아래에 만든다"
  }
}

run "scan_upload_prefix" {
  command = plan

  override_resource {
    target          = aws_s3_bucket.this["security-scans"]
    override_during = plan
    values          = { arn = "arn:aws:s3:::maemusae-security-scans-123456789012" }
  }

  assert {
    condition = alltrue([
      for repo, p in aws_iam_role_policy.scan_upload : jsondecode(p.policy).Statement == [{
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::maemusae-security-scans-123456789012/${split("/", repo)[1]}/*"
      }]
    ])
    error_message = "저장소마다 자기 <저장소 이름>/ 아래에만 PutObject"
  }
}

run "with_domain" {
  command = plan

  # 실제 DKIM 토큰은 apply 뒤에 알 수 있다
  override_resource {
    target          = aws_sesv2_email_identity.report[0]
    override_during = plan
    values = {
      dkim_signing_attributes = { tokens = ["t1", "t2", "t3"] }
    }
  }

  variables {
    route53_zone_id = "Z0000000000000"
    ses_domain      = "example.com"
  }

  assert {
    condition     = contains(keys(module.pod_identity.identities), "external-dns")
    error_message = "Route53 영역이 있으면 ExternalDNS 역할을 만든다"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.report) == 1 && length(aws_route53_record.ses_dkim) == 3
    error_message = "ses_domain 과 영역이 있으면 SES 도메인과 DKIM 레코드 3개"
  }
}

run "trim_lists" {
  command = plan

  variables {
    ecr_repositories = { web = "saebyeok-baesong/SERVICE-maemusae", ops = "saebyeok-baesong/OPS-maemusae" }
    databases        = { service = {} }
  }

  assert {
    condition     = keys(aws_ecr_repository.this) == ["ops", "web"] && keys(module.rds) == ["service"]
    error_message = "변수 목록에서 줄을 지우면 저장소와 DB 가 빠진다"
  }
}
