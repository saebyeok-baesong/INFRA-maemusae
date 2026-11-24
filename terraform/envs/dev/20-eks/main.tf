data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "${var.state_bucket_prefix}-tfstate-${var.aws_account_id}"
    key    = "dev/10-base/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  base = data.terraform_remote_state.base.outputs

  tags = {
    Project   = local.base.name
    Layer     = "eks"
    ManagedBy = "terraform"
  }
}

# NAT 는 시간당 요금이 붙어 클러스터와 함께 만들고 지운다. 출구 IP 는 10-base 의 EIP 라 매일 같다
resource "aws_nat_gateway" "this" {
  allocation_id = local.base.nat_eip_allocation_id
  subnet_id     = local.base.public_subnet_id
}

resource "aws_route" "private_nat" {
  route_table_id         = local.base.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

module "eks" {
  source = "../../../modules/eks"

  name                     = local.base.name
  kubernetes_version       = var.kubernetes_version
  private_subnet_ids_by_az = local.base.private_subnet_ids_by_az
  # 경로 ID 를 거쳐 넘겨 노드그룹만 NAT 경로를 기다리게 한다. 컨트롤 플레인은 그동안 먼저 만들어진다
  node_subnet_ids_by_az        = { for az, id in local.base.private_subnet_ids_by_az : az => id if aws_route.private_nat.id != "" }
  node_security_group_id       = local.base.node_security_group_id
  endpoint_public_access_cidrs = distinct(concat(var.endpoint_allowed_cidrs, [var.caller_cidr]))
  # apply 하는 주체는 bootstrap_cluster_creator_admin_permissions 로 이미 관리자다. 같은 주체로 항목을 또 만들면 충돌한다
  admin_principal_arns = [for arn in var.admin_principal_arns : arn if arn != data.aws_iam_session_context.current.issuer_arn]
  node_groups          = var.node_groups
  tags                 = local.tags
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = local.base.pod_identities

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn
}
