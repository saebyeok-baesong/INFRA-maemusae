# cluster 층이 terraform_remote_state 로 읽는 계약이다. 이름을 바꾸면 ../cluster 도 함께 바꾼다
output "name" {
  value = var.name
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids_by_az" {
  value = zipmap(var.azs, module.vpc.private_subnets)
}

output "private_route_table_ids" {
  value = module.vpc.private_route_table_ids
}

output "eks_clients_security_group_id" {
  value = aws_security_group.eks_clients.id
}

output "workload_identities" {
  description = "Pod Identity 연결: 키 => namespace, 서비스 계정, 역할 ARN"
  value = {
    for k, v in local.workload_identities : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.workload[k].arn
    }
  }
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

# 아래는 gitops values 에 옮겨 적을 값이다. cluster 층은 읽지 않는다
output "ecr_repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "ecr_push_role_arns" {
  description = "GitHub 저장소 => 그 저장소 CI 가 assume 할 역할 ARN"
  value       = { for k, r in aws_iam_role.ecr_push : k => r.arn }
}

output "bucket_names" {
  value = { for k, b in aws_s3_bucket.this : k => b.bucket }
}

output "databases" {
  description = "DB 키 => 접속 주소와 RDS 가 관리하는 마스터 비밀 ARN"
  value = {
    for k, db in aws_db_instance.this : k => {
      address           = db.address
      port              = db.port
      db_name           = db.db_name
      master_secret_arn = db.master_user_secret[0].secret_arn
    }
  }
}

output "app_secret_names" {
  value = [for s in aws_secretsmanager_secret.app : s.name]
}
