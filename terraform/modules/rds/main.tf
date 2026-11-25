resource "aws_db_instance" "this" {
  identifier     = var.identifier
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  db_name        = var.db_name

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  username = "maemusae"
  # RDS 가 비밀번호를 Secrets Manager 에 만들고 회전한다. Terraform state 에 비밀번호가 남지 않는다
  manage_master_user_password = true
  # 앱 사용자는 비밀번호 없이 Pod Identity 의 rds-db:connect 로 토큰을 받아 접속한다
  iam_database_authentication_enabled = true

  availability_zone      = var.availability_zone
  db_subnet_group_name   = var.subnet_group_name
  vpc_security_group_ids = var.security_group_ids
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.identifier}-final"
}

locals {
  alarms = {
    cpu = {
      metric      = "CPUUtilization"
      operator    = "GreaterThanThreshold"
      threshold   = var.alarm_thresholds.cpu_percent
      description = "CPU ${var.alarm_thresholds.cpu_percent}% 초과"
    }
    free-storage = {
      metric      = "FreeStorageSpace"
      operator    = "LessThanThreshold"
      threshold   = var.alarm_thresholds.free_storage_gib * 1024 * 1024 * 1024
      description = "남은 저장 공간 ${var.alarm_thresholds.free_storage_gib}GiB 미만"
    }
    connections = {
      metric      = "DatabaseConnections"
      operator    = "GreaterThanThreshold"
      threshold   = var.alarm_thresholds.connections
      description = "연결 ${var.alarm_thresholds.connections}개 초과"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.identifier}-${each.key}"
  alarm_description   = "${var.identifier}: ${each.value.description}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_db_instance.this.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = each.value.operator
  threshold           = each.value.threshold
  alarm_actions       = [var.alarm_topic_arn]
  ok_actions          = [var.alarm_topic_arn]
}
