data "terraform_remote_state" "base" {
  backend = "s3"
  config = {
    bucket = "${var.state_bucket_prefix}-tfstate-${var.aws_account_id}"
    key    = "base/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

locals {
  base = data.terraform_remote_state.base.outputs

  # apply 하는 주체는 enable_cluster_creator_admin_permissions 로 이미 관리자다. 같은 주체로 항목을 또 만들면 충돌한다
  admins = [for arn in var.admin_principal_arns : arn if arn != data.aws_iam_session_context.current.issuer_arn]

  # 시스템 애드온은 platform 노드에 둔다. 두 노드그룹 모두 taint 가 있어 toleration 없이는 어디에도 못 뜬다
  platform_placement = {
    nodeSelector = { role = "platform" }
    tolerations  = [{ key = "role", operator = "Equal", value = "platform", effect = "NoSchedule" }]
  }
}

################################################################################
# NAT (노드가 떠 있을 때만 필요해서 이 층에 둔다)
################################################################################
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.base.public_subnet_ids[0]
}

resource "aws_route" "private_nat" {
  for_each = toset(local.base.private_route_table_ids)

  route_table_id         = each.key
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

################################################################################
# EKS
################################################################################
# 컨트롤 플레인 로그와 고객 관리 KMS 키는 끈다. 매일 지우는 클러스터라 로그 그룹과 삭제 대기 KMS 키만 쌓인다.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.base.name
  kubernetes_version = var.kubernetes_version
  # 표준 지원이 끝나면 연장 지원 요금(시간당 6배) 대신 자동 업그레이드된다
  upgrade_policy = { support_type = "STANDARD" }

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = distinct(concat(var.endpoint_allowed_cidrs, [var.caller_cidr]))

  vpc_id     = local.base.vpc_id
  subnet_ids = values(local.base.private_subnet_ids_by_az)

  create_kms_key              = false
  encryption_config           = null
  create_cloudwatch_log_group = false
  enabled_log_types           = []

  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for i, arn in local.admins : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = { configuration_values = jsonencode(local.platform_placement) }
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = local.base.ebs_csi_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
      configuration_values = jsonencode({
        controller = merge(local.platform_placement, {
          # PVC 로 생긴 EBS 볼륨에도 태그를 붙여 eks.sh leftovers 가 찾게 한다
          extraVolumeTags = { Project = local.base.name, Layer = "cluster" }
        })
      })
    }
  }

  # EBS 볼륨이 AZ 에 묶여서 노드그룹마다 서브넷 하나에 고정한다
  eks_managed_node_groups = {
    for k, ng in var.node_groups : k => {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = [ng.instance_type]
      subnet_ids     = [local.base.private_subnet_ids_by_az[ng.az]]
      min_size       = ng.size
      max_size       = ng.size
      desired_size   = ng.size
      labels         = { role = k }
      taints         = { role = { key = "role", value = k, effect = "NO_SCHEDULE" } }

      vpc_security_group_ids = [local.base.eks_clients_security_group_id]

      use_name_prefix = false
      # 매일 새로 만드는 노드그룹이라 EKS 가 그때의 최신 AMI 를 고른다
      use_latest_ami_release_version = false
    }
  }
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each = local.base.workload_identities

  cluster_name    = module.eks.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn
}

################################################################################
# Argo CD (앱과 나머지 애드온은 이 레포 gitops/ 에서 Argo CD 가 설치한다)
################################################################################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version

  # 접속은 kubectl port-forward. LoadBalancer 를 만들지 않는다
  values = [yamlencode({
    global        = local.platform_placement
    dex           = { enabled = false }
    notifications = { enabled = false }
    server        = { service = { type = "ClusterIP" } }
  })]

  depends_on = [module.eks]
}
