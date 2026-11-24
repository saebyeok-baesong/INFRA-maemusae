# Pod Identity 역할은 클러스터와 따로 늘 켜 둔다. 매일 다시 만들어도 ARN 이 그대로라 정책 검토와 CloudTrail 기록이 이어진다.
# 연결(aws_eks_pod_identity_association)은 클러스터가 있어야 해서 20-eks 가 만든다.
# 정책 문서는 보안팀이 리뷰하는 iam/policies 에 둔다 (CODEOWNERS)
locals {
  policy_dir = "${path.module}/../../../../iam/policies"

  policy_vars = {
    loki_bucket_arn    = aws_s3_bucket.this["loki"].arn
    uploads_bucket_arn = aws_s3_bucket.this["uploads"].arn
    scans_bucket_arn   = aws_s3_bucket.this["security-scans"].arn
    hosted_zone_arn    = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
    secret_arns = concat(
      ["arn:aws:secretsmanager:${var.region}:${var.aws_account_id}:secret:${var.name}/*"],
      [for db in module.rds : db.master_secret_arn],
    )
  }
}

module "pod_identity" {
  source = "../../../modules/pod-identity"

  name = var.name
  identities = merge(
    {
      aws-load-balancer-controller = { namespace = "kube-system", service_account = "aws-load-balancer-controller", policy_json = file("${local.policy_dir}/aws-load-balancer-controller.json") }
      external-secrets             = { namespace = "external-secrets", service_account = "external-secrets", policy_json = templatefile("${local.policy_dir}/external-secrets.json.tftpl", local.policy_vars) }
      loki                         = { namespace = "monitoring", service_account = "loki", policy_json = templatefile("${local.policy_dir}/loki.json.tftpl", local.policy_vars) }
      api                          = { namespace = "maemusae", service_account = "api", policy_json = templatefile("${local.policy_dir}/api.json.tftpl", local.policy_vars) }
      ebs-csi                      = { namespace = "kube-system", service_account = "ebs-csi-controller-sa", managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"] }
      ops-security-ingest          = { namespace = "incident", service_account = "ops-security-ingest", policy_json = templatefile("${local.policy_dir}/ops-security-ingest.json.tftpl", local.policy_vars) }
    },
    var.route53_zone_id == "" ? {} : {
      external-dns = { namespace = "external-dns", service_account = "external-dns", policy_json = templatefile("${local.policy_dir}/external-dns.json.tftpl", local.policy_vars) }
    },
  )
}

# bootstrap 이 만든 공급자를 읽는다
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  ecr_pushers = toset(values(var.ecr_repositories))
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

# 스캔은 PR 에서도 돌아서 main 만 믿는 ECR push 역할과 따로 둔다. 합치면 PR 이 이미지를 push 할 수 있게 된다
data "aws_iam_policy_document" "scan_upload_trust" {
  for_each = toset(var.security_scan_repositories)

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
      values   = ["repo:${each.key}:ref:refs/heads/main", "repo:${each.key}:pull_request"]
    }
  }
}

resource "aws_iam_role" "scan_upload" {
  for_each = toset(var.security_scan_repositories)

  name               = "${var.name}-gha-scan-${lower(split("/", each.key)[1])}"
  description        = "GitHub Actions security scan upload from ${each.key}"
  assume_role_policy = data.aws_iam_policy_document.scan_upload_trust[each.key].json
}

resource "aws_iam_role_policy" "scan_upload" {
  for_each = toset(var.security_scan_repositories)

  name = "security-scan-upload"
  role = aws_iam_role.scan_upload[each.key].id
  policy = templatefile("${local.policy_dir}/github-security-scan-upload.json.tftpl", {
    scans_bucket_arn = aws_s3_bucket.this["security-scans"].arn
    repo             = split("/", each.key)[1]
  })
}
