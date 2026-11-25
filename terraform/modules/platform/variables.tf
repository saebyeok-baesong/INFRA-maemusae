variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "region" {
  description = "AWS 리전"
  type        = string
}

variable "vpc_id" {
  description = "LB Controller 가 NLB 를 만들 VPC"
  type        = string
}

variable "pod_identities" {
  description = "10-base 의 Pod Identity 표. 서비스 계정 이름을 여기서 읽어 연결과 어긋나지 않게 한다. external-dns 키가 있을 때만 ExternalDNS 를 설치한다"
  type = map(object({
    namespace       = string
    service_account = string
    role_arn        = string
  }))
}

variable "route53_zone_id" {
  description = "ExternalDNS 가 레코드를 쓸 호스팅 영역"
  type        = string
}

variable "chart_versions" {
  description = "Helm 차트 버전"
  type = object({
    aws_load_balancer_controller = string
    external_secrets             = string
    external_dns                 = string
    argocd                       = string
    argocd_apps                  = string
  })
}

variable "gitops_repo_url" {
  description = "Argo CD root 앱이 gitops/apps/ 를 읽을 저장소"
  type        = string
}
