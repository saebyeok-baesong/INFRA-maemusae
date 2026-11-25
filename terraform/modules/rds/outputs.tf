output "identifier" {
  value = aws_db_instance.this.identifier
}

output "arn" {
  value = aws_db_instance.this.arn
}

output "resource_id" {
  description = "rds-db:connect 정책의 dbuser ARN 에 들어가는 ID"
  value       = aws_db_instance.this.resource_id
}

output "availability_zone" {
  value = aws_db_instance.this.availability_zone
}

output "address" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_secret_arn" {
  description = "RDS 가 관리하는 마스터 비밀. External Secrets 가 읽는다"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "alarm_names" {
  value = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]
}
