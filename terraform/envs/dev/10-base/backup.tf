# service DB 만 월 1회 스냅샷을 받아 90일 보관한다. RDS 자동 백업(7일 PITR)보다 오래 남길 복구 지점이다.
# 선택은 태그가 아니라 ARN 이다. 태그로 고르면 다른 DB 에 태그만 붙여도 백업 대상에 들어온다
resource "aws_backup_vault" "service" {
  name = "${var.name}-service"
}

resource "aws_backup_plan" "service" {
  name = "${var.name}-service-monthly"

  rule {
    rule_name         = "monthly"
    target_vault_name = aws_backup_vault.service.name
    # 매월 1일 10:00 KST. 서울 리전 RDS 기본 백업 창(22:00-06:00 KST)과 겹치면 작업이 밀리거나 실패한다
    schedule                     = "cron(0 10 1 * ? *)"
    schedule_expression_timezone = "Asia/Seoul"
    start_window                 = 60
    completion_window            = 360

    lifecycle {
      delete_after = var.service_backup_retention_days
    }
  }
}

data "aws_iam_policy_document" "backup_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "${var.name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_trust.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

resource "aws_backup_selection" "service" {
  name         = "${var.name}-service"
  plan_id      = aws_backup_plan.service.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = [module.rds["service"].arn]
}
