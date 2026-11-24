locals {
  # 20-eks 가 platform 노드에 role=platform:NoSchedule taint 를 건다
  platform_placement = {
    nodeSelector = { role = "platform" }
    tolerations  = [{ key = "role", operator = "Equal", value = "platform", effect = "NoSchedule" }]
  }

  lbc         = var.pod_identities["aws-load-balancer-controller"]
  eso         = var.pod_identities["external-secrets"]
  externaldns = lookup(var.pod_identities, "external-dns", null)
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.lbc.namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions.aws_load_balancer_controller

  # 노드 IMDS 홉 제한이 1 이라 Pod 가 IMDS 로 리전과 VPC 를 찾지 못한다. 직접 넘긴다
  values = [yamlencode(merge(local.platform_placement, {
    clusterName    = var.cluster_name
    region         = var.region
    vpcId          = var.vpc_id
    replicaCount   = 1
    serviceAccount = { create = true, name = local.lbc.service_account }
  }))]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = local.eso.namespace
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.chart_versions.external_secrets

  values = [yamlencode({
    global         = local.platform_placement
    serviceAccount = { create = true, name = local.eso.service_account }
  })]

  # LB Controller 웹훅이 Service 생성을 가로챈다. 컨트롤러가 뜨기 전에 다른 차트가 Service 를 만들면 실패한다
  depends_on = [helm_release.aws_load_balancer_controller]
}

resource "helm_release" "external_dns" {
  count = local.externaldns == null ? 0 : 1

  name             = "external-dns"
  namespace        = local.externaldns.namespace
  create_namespace = true
  repository       = "https://kubernetes-sigs.github.io/external-dns"
  chart            = "external-dns"
  version          = var.chart_versions.external_dns

  # policy=sync 라야 eks.sh down 이 Service 를 지울 때 Route53 레코드도 지운다
  values = [yamlencode(merge(local.platform_placement, {
    provider       = { name = "aws" }
    policy         = "sync"
    txtOwnerId     = var.cluster_name
    extraArgs      = ["--zone-id-filter=${var.route53_zone_id}"]
    env            = [{ name = "AWS_REGION", value = var.region }]
    serviceAccount = { create = true, name = local.externaldns.service_account }
  }))]

  depends_on = [helm_release.aws_load_balancer_controller]
}

# 접속은 kubectl port-forward. LoadBalancer 를 만들지 않는다
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_versions.argocd

  values = [yamlencode({
    global        = local.platform_placement
    dex           = { enabled = false }
    notifications = { enabled = false }
    server        = { service = { type = "ClusterIP" } }
  })]

  depends_on = [helm_release.aws_load_balancer_controller]
}
