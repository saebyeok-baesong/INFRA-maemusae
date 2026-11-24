# 정책 문서는 보안팀 소유인 iam/policies 에 둔다 (CODEOWNERS)
locals {
  policy_dir = "${path.module}/../../iam/policies"

  policy_vars = {
    loki_bucket_arn    = aws_s3_bucket.this["loki"].arn
    uploads_bucket_arn = aws_s3_bucket.this["uploads"].arn
    hosted_zone_arn    = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
    secret_arns = concat(
      [for s in aws_secretsmanager_secret.app : s.arn],
      [for db in aws_db_instance.this : db.master_user_secret[0].secret_arn],
    )
  }

  # cluster 층이 이 표대로 Pod Identity 연결을 만든다. namespace 와 서비스 계정은 gitops 매니페스트와의 계약이다
  workload_identities = merge(
    {
      aws-load-balancer-controller = { namespace = "kube-system", service_account = "aws-load-balancer-controller", policy = file("${local.policy_dir}/aws-load-balancer-controller.json") }
      external-secrets             = { namespace = "external-secrets", service_account = "external-secrets", policy = templatefile("${local.policy_dir}/external-secrets.json.tftpl", local.policy_vars) }
      loki                         = { namespace = "monitoring", service_account = "loki", policy = templatefile("${local.policy_dir}/loki.json.tftpl", local.policy_vars) }
      api                          = { namespace = "maemusae", service_account = "api", policy = templatefile("${local.policy_dir}/api.json.tftpl", local.policy_vars) }
    },
    var.route53_zone_id == "" ? {} : {
      external-dns = { namespace = "external-dns", service_account = "external-dns", policy = templatefile("${local.policy_dir}/external-dns.json.tftpl", local.policy_vars) }
    },
  )

  ecr_pushers = toset(values(var.ecr_repositories))
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.workload_identities

  name               = "${var.name}-${each.key}"
  description        = "Pod Identity for ${each.value.namespace}/${each.value.service_account}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.workload_identities

  name   = each.key
  role   = aws_iam_role.workload[each.key].id
  policy = each.value.policy
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  description        = "Pod Identity for kube-system/ebs-csi-controller-sa (EBS CSI add-on)"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# bootstrap 이 만든 공급자를 읽는다
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "ecr_push_trust" {
  for_each = local.ecr_pushers

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${each.key}:ref:${var.ecr_push_ref}"]
    }
  }
}

resource "aws_iam_role" "ecr_push" {
  for_each = local.ecr_pushers

  name               = "${var.name}-gha-ecr-${lower(split("/", each.key)[1])}"
  description        = "GitHub Actions ECR push from ${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ecr_push_trust[each.key].json
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = local.ecr_pushers

  name = "ecr-push"
  role = aws_iam_role.ecr_push[each.key].id
  policy = templatefile("${local.policy_dir}/github-ecr-push.json.tftpl", {
    repository_arns = [for name, repo in var.ecr_repositories : aws_ecr_repository.this[name].arn if repo == each.key]
  })
}
