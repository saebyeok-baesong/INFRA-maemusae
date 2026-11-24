resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = values(module.network.db_subnet_ids_by_az)
}

module "rds" {
  source   = "../../../modules/rds"
  for_each = var.databases

  identifier         = "${var.name}-${each.key}"
  db_name            = each.key
  engine_version     = each.value.engine_version
  instance_class     = each.value.instance_class
  allocated_storage  = each.value.allocated_storage
  availability_zone  = var.rds_availability_zone
  subnet_group_name  = aws_db_subnet_group.this.name
  security_group_ids = [module.network.rds_security_group_id]

  backup_retention_days = var.rds_backup_retention_days
  deletion_protection   = var.rds_deletion_protection
  alarm_topic_arn       = aws_sns_topic.alerts.arn
  alarm_thresholds      = var.rds_alarm_thresholds
}

# 장애 조치, 저장 공간 부족, 유지 관리 같은 RDS 이벤트를 경보와 같은 주제로 보낸다.
# 같은 계정의 RDS 는 주제 기본 정책으로 게시할 수 있어 주제 정책을 따로 두지 않는다
resource "aws_db_event_subscription" "rds" {
  name        = "${var.name}-rds"
  sns_topic   = aws_sns_topic.alerts.arn
  source_type = "db-instance"
  source_ids  = [for db in module.rds : db.identifier]
  event_categories = [
    "availability",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "notification",
    "recovery",
  ]
}

# Prometheus TSDB 를 클러스터보다 오래 남긴다. gitops 의 정적 PV(Retain)가 이 볼륨을 platform 노드에 붙인다.
# ebs.csi.aws.com/cluster 태그를 달지 않는다. EBS CSI 정책은 그 태그가 있는 볼륨만 지울 수 있다
resource "aws_ebs_volume" "prometheus" {
  availability_zone = var.prometheus_volume.az
  size              = var.prometheus_volume.size_gib
  type              = "gp3"
  encrypted         = true
  final_snapshot    = true

  tags = {
    Name    = "${var.name}-prometheus"
    Purpose = "prometheus-tsdb"
  }
}

locals {
  # expire_days = null 이면 객체를 지우지 않는다
  buckets = {
    uploads    = { force_destroy = false, expire_days = null }
    loki       = { force_destroy = true, expire_days = var.loki_retention_days }
    cloudtrail = { force_destroy = false, expire_days = var.cloudtrail_retention_days }
    # SERVICE, OPS, INFRA CI 가 올리고 incident 의 ops-security-ingest 가 읽는다
    security-scans = { force_destroy = false, expire_days = var.security_scan_retention_days }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.name}-${each.key}-${var.aws_account_id}"
  force_destroy = each.value.force_destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
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
