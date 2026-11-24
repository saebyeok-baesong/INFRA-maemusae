# 토큰을 apply 중에 받는다. plan 때 받은 토큰은 15분 뒤 만료돼 긴 설치 중간에 끊긴다
provider "helm" {
  kubernetes = {
    host                   = local.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks.cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.eks.cluster_name, "--region", local.base.region]
    }
  }
}
