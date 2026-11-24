output "state_bucket" {
  description = "envs/dev/* 의 backend bucket"
  value       = module.state_bucket.s3_bucket_id
}

output "plan_role_arn" {
  description = "GitHub 변수 AWS_PLAN_ROLE_ARN"
  value       = module.plan_role.arn
}

output "apply_role_arn" {
  description = "GitHub 변수 AWS_APPLY_ROLE_ARN. 20-eks 의 admin_principal_arns 에도 넣는다"
  value       = module.apply_role.arn
}
