locals {
  # 두 노드그룹 모두 taint 가 있어 toleration 이 없는 Pod 는 어디에도 못 뜬다. 시스템 애드온은 platform 노드에 둔다
  platform_placement = {
    nodeSelector = { role = "platform" }
    tolerations  = [{ key = "role", operator = "Equal", value = "platform", effect = "NoSchedule" }]
  }
}

data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 컨트롤 플레인 로그와 봉투 암호화용 KMS 키는 켜지 않는다. 매일 지우는 클러스터라 로그 그룹과 삭제 대기 키만 쌓인다
resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # vpc-cni, coredns, kube-proxy 를 아래 aws_eks_addon 으로만 관리한다
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = values(var.private_subnet_ids_by_az)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  # 표준 지원이 끝나면 연장 지원 요금 대신 자동 업그레이드된다
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.key
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = aws_eks_access_entry.admin

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

data "aws_iam_policy_document" "node_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_trust.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    # SSH 키와 22 포트 없이 Session Manager 로 노드에 들어간다
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.key
}

# 보안 그룹을 지정하면 EKS 가 클러스터 보안 그룹을 붙이지 않아서 직접 함께 넣는다.
# 클러스터 보안 그룹은 컨트롤 플레인과 노드 사이 통신을, 노드 보안 그룹(10-base)은 RDS 접근을 연다
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name = "${var.name}-${each.key}"
  vpc_security_group_ids = [
    aws_eks_cluster.this.vpc_config[0].cluster_security_group_id,
    var.node_security_group_id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # 노드 EC2 와 루트 볼륨에 태그를 붙여 eks.sh leftovers 가 찾게 한다
  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])
    content {
      resource_type = tag_specifications.key
      tags          = merge(var.tags, { Name = "${var.name}-${each.key}" })
    }
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  # EBS 볼륨이 AZ 에 묶여서 노드그룹마다 서브넷 하나에 고정한다
  subnet_ids     = [var.node_subnet_ids_by_az[each.value.az]]
  ami_type       = "AL2023_ARM_64_STANDARD"
  instance_types = [each.value.instance_type]

  scaling_config {
    min_size     = each.value.size
    max_size     = each.value.size
    desired_size = each.value.size
  }

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  labels = { role = each.key }

  taint {
    key    = "role"
    value  = each.key
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}

# 노드가 Ready 가 되려면 CNI 가, Pod Identity 를 쓰는 Pod 가 뜨려면 에이전트가 먼저 있어야 한다
resource "aws_eks_addon" "before_nodes" {
  for_each = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# Deployment 로 뜨는 애드온은 노드가 없으면 ACTIVE 가 되지 않는다
resource "aws_eks_addon" "after_nodes" {
  for_each = {
    coredns = local.platform_placement
    aws-ebs-csi-driver = {
      controller = merge(local.platform_placement, {
        # PVC 로 생긴 EBS 볼륨에도 태그를 붙여 eks.sh leftovers 가 찾게 한다
        extraVolumeTags = var.tags
      })
    }
  }

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  configuration_values        = jsonencode(each.value)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
