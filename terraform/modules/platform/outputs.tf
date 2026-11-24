output "releases" {
  description = "설치한 Helm 릴리스 이름"
  value = sort(concat(
    [helm_release.aws_load_balancer_controller.name, helm_release.external_secrets.name, helm_release.argocd.name],
    helm_release.external_dns[*].name,
  ))
}
