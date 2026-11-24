# 20-eks, 30-platform 이 terraform_remote_state 로 읽는 계약이다. 이름을 바꾸면 두 층도 함께 바꾼다
output "name" {
  value = var.name
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids_by_az" {
  value = module.network.private_subnet_ids_by_az
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "nat_eip_allocation_id" {
  value = module.network.nat_eip_allocation_id
}

output "node_security_group_id" {
  value = module.network.node_security_group_id
}

output "pod_identities" {
  description = "키 => namespace, service_account, role_arn"
  value       = module.pod_identity.identities
}

output "route53_zone_id" {
  value = var.route53_zone_id
}

# 아래는 gitops values 와 다른 레포 CI 설정에 옮겨 적을 값이다
output "nat_public_ip" {
  value = module.network.nat_public_ip
}

output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "ecr_push_role_arns" {
  description = "GitHub 저장소 => 그 저장소 CI 가 assume 할 역할 ARN"
  value       = { for k, r in aws_iam_role.ecr_push : k => r.arn }
}

output "security_scan_bucket" {
  description = "스캔 결과 버킷. 키는 <저장소 이름>/<도구>/<YYYY-MM-DD>/<github_run_id>.json"
  value       = aws_s3_bucket.this["security-scans"].bucket
}

output "security_scan_role_arns" {
  description = "GitHub 저장소 => 스캔 결과를 올릴 때 assume 할 역할 ARN"
  value       = { for k, r in aws_iam_role.scan_upload : k => r.arn }
}

output "bucket_names" {
  value = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "databases" {
  description = "DB 키 => 접속 주소와 RDS 가 관리하는 마스터 비밀 ARN"
  value = {
    for k, db in module.rds : k => {
      address           = db.address
      port              = db.port
      db_name           = db.db_name
      master_secret_arn = db.master_secret_arn
    }
  }
}

output "app_secret_names" {
  value = [for s in aws_secretsmanager_secret.app : s.name]
}
