data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.identities

  name               = "${var.name}-${each.key}"
  description        = "Pod Identity for ${each.value.namespace}/${each.value.service_account}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "this" {
  for_each = { for k, v in var.identities : k => v if v.policy_json != null }

  name   = each.key
  role   = aws_iam_role.this[each.key].id
  policy = each.value.policy_json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = merge([
    for k, v in var.identities : { for arn in v.managed_policy_arns : "${k} ${arn}" => { role = k, arn = arn } }
  ]...)

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}
