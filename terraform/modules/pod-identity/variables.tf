variable "name" {
  description = "역할 이름 접두사"
  type        = string
}

variable "identities" {
  description = "키 => Pod Identity 로 역할을 받을 서비스 계정과 권한. namespace, service_account 는 Helm values, gitops 매니페스트와의 계약이다"
  type = map(object({
    namespace           = string
    service_account     = string
    policy_json         = optional(string)
    managed_policy_arns = optional(list(string), [])
  }))
}
