data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "${var.state_bucket_prefix}-tfstate-${var.aws_account_id}"
    key    = "dev/10-base/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "${var.state_bucket_prefix}-tfstate-${var.aws_account_id}"
    key    = "dev/20-eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  base = data.terraform_remote_state.base.outputs
  eks  = data.terraform_remote_state.eks.outputs
}

# LB Controller, External Secrets, ExternalDNS, Argo CD 만 설치한다. 나머지 애드온과 앱은 Argo CD 가 gitops/ 에서 설치한다
module "platform" {
  source = "../../../modules/platform"

  cluster_name    = local.eks.cluster_name
  region          = local.base.region
  vpc_id          = local.base.vpc_id
  pod_identities  = local.base.pod_identities
  route53_zone_id = local.base.route53_zone_id
  chart_versions  = var.chart_versions
}
