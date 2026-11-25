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
    condition     = keys(module.rds) == ["ops", "service"]
    error_message = "service 와 ops DB 2개. incident, security 는 ops 안의 DB 다"
  }

  assert {
    condition     = alltrue([for db in module.rds : length(db.alarm_names) == 3])
    error_message = "DB 마다 CPU, 저장 공간, 연결 경보"
  }

  assert {
    condition     = keys(aws_ecr_repository.this) == ["api", "ops", "web"]
    error_message = "ECR 저장소는 SERVICE 의 web, api 와 OPS 이미지 하나(ops)"
  }

  assert {
    condition     = keys(aws_ecr_lifecycle_policy.this) == keys(aws_ecr_repository.this)
    error_message = "ECR 저장소마다 수명 주기 정책"
  }

  assert {
    condition     = keys(aws_iam_role.ecr_push) == ["saebyeok-baesong/OPS-watch-nyang", "saebyeok-baesong/SERVICE-watch-nyang"]
    error_message = "ECR push 역할은 GitHub 저장소마다 하나"
  }

  assert {
    condition     = keys(module.pod_identity.identities) == ["api", "aws-load-balancer-controller", "ebs-csi", "external-secrets", "loki", "ops", "ops-security-ingest"]
    error_message = "Route53 영역이 없으면 ExternalDNS 역할을 만들지 않는다"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.report) == 0 && length(aws_route53_record.ses_dkim) == 0
    error_message = "ses_domain 이 비면 SES 를 만들지 않는다"
  }

  assert {
    condition     = aws_s3_bucket.this["public"].bucket == "maemusae-public-123456789012" && aws_s3_bucket.this["private"].bucket == "maemusae-private-123456789012" && alltrue([for b in aws_s3_bucket.this : !b.force_destroy])
    error_message = "버킷은 public, private 2개이고 객체가 있으면 지우지 않는다"
  }

  assert {
    condition     = keys(aws_s3_bucket_server_side_encryption_configuration.this) == ["private", "public"] && keys(aws_s3_bucket_public_access_block.this) == keys(aws_s3_bucket.this)
    error_message = "모든 버킷에 SSE 와 퍼블릭 차단 설정"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this["private"].block_public_policy && aws_s3_bucket_public_access_block.this["private"].restrict_public_buckets &&
      !aws_s3_bucket_public_access_block.this["public"].block_public_policy && !aws_s3_bucket_public_access_block.this["public"].restrict_public_buckets &&
      alltrue([for b in aws_s3_bucket_public_access_block.this : b.block_public_acls && b.ignore_public_acls])
    )
    error_message = "public 만 버킷 정책으로 공개하고 ACL 공개는 둘 다 막는다"
  }

  assert {
    condition = {
      for r in aws_s3_bucket_lifecycle_configuration.private.rule : r.id => [one(r.filter).prefix, try(one(r.expiration).days, null)] if length(r.expiration) > 0
      } == {
      expire-cloudtrail     = ["cloudtrail/", 365]
      expire-loki           = ["loki/", 14]
      expire-security-scans = ["security-scans/", 90]
    }
    error_message = "private 은 접두사마다 만료 규칙이 있고 mms/ 는 지우지 않는다"
  }

  assert {
    condition     = aws_cloudtrail.this.s3_key_prefix == "cloudtrail" && output.security_scan_prefix == "security-scans/"
    error_message = "CloudTrail 과 스캔 결과는 private 버킷의 접두사 아래에 쌓인다"
  }

  assert {
    condition     = module.pod_identity.identities["ops-security-ingest"].namespace == "incident" && module.pod_identity.identities["ops-security-ingest"].service_account == "ops-security-ingest"
    error_message = "스캔 수집기는 incident/ops-security-ingest"
  }

  assert {
    condition     = module.pod_identity.identities["ops"].namespace == "incident" && module.pod_identity.identities["ops"].service_account == "ops"
    error_message = "OPS 앱은 incident/ops"
  }

  assert {
    condition     = keys(aws_iam_role.scan_upload) == ["saebyeok-baesong/INFRA-watch-nyang", "saebyeok-baesong/OPS-watch-nyang", "saebyeok-baesong/SERVICE-watch-nyang"]
    error_message = "스캔 업로드 역할은 SERVICE, OPS, INFRA 마다 하나"
  }

  assert {
    condition     = aws_secretsmanager_secret.app["openai"].name == "maemusae/openai" && aws_secretsmanager_secret.app["github-rollback-app"].name == "maemusae/github-rollback-app"
    error_message = "앱 비밀과 롤백 App 키는 External Secrets 가 읽는 maemusae/ 아래에 만든다"
  }

  assert {
    condition     = aws_sns_topic_subscription.alerts_email.protocol == "email" && aws_sns_topic_subscription.alerts_discord.protocol == "lambda"
    error_message = "alerts 주제는 메일과 Discord Lambda 로 함께 보낸다"
  }

  assert {
    condition     = aws_lambda_function.discord_alerts.runtime == "python3.13" && aws_lambda_function.discord_alerts.architectures == tolist(["arm64"]) && aws_cloudwatch_log_group.discord_alerts.retention_in_days == 14
    error_message = "Discord Lambda 는 python3.13 arm64, 로그는 14일"
  }
}

# subnet id, ARN 은 apply 뒤에 정해져서 plan 에서 비교하려면 값을 정해 둔다
run "rds_wiring" {
  command = plan

  override_resource {
    target          = module.network.aws_subnet.db["ap-northeast-2a"]
    override_during = plan
    values          = { id = "subnet-db-2a" }
  }

  override_resource {
    target          = module.network.aws_subnet.db["ap-northeast-2c"]
    override_during = plan
    values          = { id = "subnet-db-2c" }
  }

  override_resource {
    target          = module.network.aws_subnet.private["ap-northeast-2a"]
    override_during = plan
    values          = { id = "subnet-node-2a" }
  }

  override_resource {
    target          = module.network.aws_subnet.private["ap-northeast-2c"]
    override_during = plan
    values          = { id = "subnet-node-2c" }
  }

  override_resource {
    target          = module.rds["service"].aws_db_instance.this
    override_during = plan
    values          = { arn = "arn:aws:rds:ap-northeast-2:123456789012:db:maemusae-service", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!maemusae-service" }] }
  }

  override_resource {
    target          = module.rds["ops"].aws_db_instance.this
    override_during = plan
    values          = { arn = "arn:aws:rds:ap-northeast-2:123456789012:db:maemusae-ops", resource_id = "db-OPS", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!maemusae-ops" }] }
  }

  override_resource {
    target          = aws_sns_topic.alerts
    override_during = plan
    values          = { arn = "arn:aws:sns:ap-northeast-2:123456789012:maemusae-alerts" }
  }

  assert {
    condition     = toset(aws_db_subnet_group.this.subnet_ids) == toset(["subnet-db-2a", "subnet-db-2c"])
    error_message = "RDS 서브넷 그룹에는 DB 서브넷 2a, 2c 만 들어간다"
  }

  assert {
    condition     = alltrue([for db in module.rds : db.availability_zone == "ap-northeast-2a"])
    error_message = "RDS 2개 모두 2a 에 둔다"
  }

  assert {
    condition     = aws_db_event_subscription.rds.source_type == "db-instance" && aws_db_event_subscription.rds.source_ids == toset(["maemusae-ops", "maemusae-service"])
    error_message = "RDS 이벤트 구독은 DB 2개를 모두 받는다"
  }

  assert {
    condition     = aws_db_event_subscription.rds.sns_topic == "arn:aws:sns:ap-northeast-2:123456789012:maemusae-alerts"
    error_message = "RDS 이벤트는 CloudWatch 경보와 같은 alerts 주제로 간다"
  }

  assert {
    condition     = local.policy_vars.ops_dbuser_arn == "arn:aws:rds-db:ap-northeast-2:123456789012:dbuser:db-OPS"
    error_message = "rds-db:connect 는 ops 인스턴스의 리소스 ID 로 dbuser 를 가리킨다"
  }
}

run "prometheus_volume" {
  command = plan

  assert {
    condition     = aws_ebs_volume.prometheus.availability_zone == "ap-northeast-2c"
    error_message = "Prometheus 볼륨은 20-eks 의 platform 노드그룹과 같은 2c 에 둔다. 한쪽을 바꾸면 20-eks 테스트의 같은 값도 바꾼다"
  }

  assert {
    condition     = aws_ebs_volume.prometheus.encrypted && aws_ebs_volume.prometheus.type == "gp3" && aws_ebs_volume.prometheus.final_snapshot
    error_message = "Prometheus 볼륨은 암호화한 gp3 이고 지울 때 마지막 스냅샷을 남긴다"
  }

  assert {
    condition     = !contains(keys(aws_ebs_volume.prometheus.tags), "ebs.csi.aws.com/cluster")
    error_message = "EBS CSI 가 지울 수 있는 태그를 달지 않는다"
  }
}

run "private_prefixes" {
  command = plan

  override_resource {
    target          = aws_s3_bucket.this["private"]
    override_during = plan
    values          = { arn = "arn:aws:s3:::maemusae-private-123456789012" }
  }

  override_resource {
    target          = aws_s3_bucket.this["public"]
    override_during = plan
    values          = { arn = "arn:aws:s3:::maemusae-public-123456789012" }
  }

  # 정책 템플릿 변수에 RDS 리소스 ID 와 마스터 비밀 ARN 도 들어간다
  override_resource {
    target          = module.rds["ops"].aws_db_instance.this
    override_during = plan
    values          = { resource_id = "db-OPS", master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!maemusae-ops" }] }
  }

  override_resource {
    target          = module.rds["service"].aws_db_instance.this
    override_during = plan
    values          = { master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:ap-northeast-2:123456789012:secret:rds!maemusae-service" }] }
  }

  assert {
    condition = alltrue([
      for repo, p in aws_iam_role_policy.scan_upload : jsondecode(p.policy).Statement == [{
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::maemusae-private-123456789012/security-scans/${split("/", repo)[1]}/*"
      }]
    ])
    error_message = "저장소마다 자기 security-scans/<저장소 이름>/ 아래에만 PutObject"
  }

  assert {
    condition     = jsondecode(templatefile("${local.policy_dir}/api.json.tftpl", local.policy_vars)).Statement[2].Resource == ["arn:aws:s3:::maemusae-public-123456789012/*", "arn:aws:s3:::maemusae-private-123456789012/mms/*"]
    error_message = "api 는 public 전체와 private mms/ 를 읽고 쓴다"
  }

  assert {
    condition = alltrue([
      for f, prefix in { "api.json.tftpl" = "mms/*", "loki.json.tftpl" = "loki/*", "ops-security-ingest.json.tftpl" = "security-scans/*" } :
      contains([for st in jsondecode(templatefile("${local.policy_dir}/${f}", local.policy_vars)).Statement : try(st.Condition.StringLike["s3:prefix"], null) if st.Resource == "arn:aws:s3:::maemusae-private-123456789012"], [prefix])
    ])
    error_message = "private 버킷 목록은 자기 접두사로만 볼 수 있다"
  }

  assert {
    condition     = jsondecode(templatefile("${local.policy_dir}/loki.json.tftpl", local.policy_vars)).Statement[1].Resource == "arn:aws:s3:::maemusae-private-123456789012/loki/*" && jsondecode(templatefile("${local.policy_dir}/ops-security-ingest.json.tftpl", local.policy_vars)).Statement[1].Resource == "arn:aws:s3:::maemusae-private-123456789012/security-scans/*"
    error_message = "loki 는 loki/, 스캔 수집기는 security-scans/ 객체만"
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
    ecr_repositories = { web = "saebyeok-baesong/SERVICE-watch-nyang", ops = "saebyeok-baesong/OPS-watch-nyang" }
    databases        = { ops = {} }
  }

  assert {
    condition     = keys(aws_ecr_repository.this) == ["ops", "web"] && keys(module.rds) == ["ops"]
    error_message = "변수 목록에서 줄을 지우면 저장소와 DB 가 빠진다"
  }
}

run "ops_db_required" {
  command = plan

  variables {
    databases = { service = {} }
  }

  expect_failures = [var.databases]
}
