output "identities" {
  description = "키 => namespace, service_account, role_arn. 20-eks 가 이 표대로 Pod Identity 연결을 만든다"
  value = {
    for k, v in var.identities : k => {
      namespace       = v.namespace
      service_account = v.service_account
      role_arn        = aws_iam_role.this[k].arn
    }
  }
}
