# AWS 에 접속하지 않는 plan. 10-base 의 output 을 아래 값으로 흉내 낸다. terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/tester" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/tester" }
  }
}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      name                     = "maemusae"
      private_subnet_ids_by_az = { "ap-northeast-2a" = "subnet-priv-a", "ap-northeast-2c" = "subnet-priv-c" }
      node_security_group_id   = "sg-node"
      public_subnet_id         = "subnet-pub-a"
      private_route_table_id   = "rtb-priv"
      nat_eip_allocation_id    = "eipalloc-0123"
      pod_identities = {
        loki    = { namespace = "monitoring", service_account = "loki", role_arn = "arn:aws:iam::123456789012:role/maemusae-loki" }
        ebs-csi = { namespace = "kube-system", service_account = "ebs-csi-controller-sa", role_arn = "arn:aws:iam::123456789012:role/maemusae-ebs-csi" }
      }
    }
  }
}

variables {
  aws_account_id       = "123456789012"
  caller_cidr          = "203.0.113.10/32"
  admin_principal_arns = ["arn:aws:iam::123456789012:user/tester", "arn:aws:iam::123456789012:role/maemusae-gha-apply"]
}

run "default" {
  command = plan

  # 노드그룹 서브넷이 NAT 경로 ID 를 거쳐 오므로 plan 에서 알 수 있게 한다
  override_resource {
    target          = aws_route.private_nat
    override_during = plan
    values          = { id = "r-rtb-priv1080289494" }
  }

  assert {
    condition     = aws_nat_gateway.this.subnet_id == "subnet-pub-a" && aws_nat_gateway.this.allocation_id == "eipalloc-0123"
    error_message = "NAT 는 퍼블릭 2a 에 10-base 의 EIP 로 만든다"
  }

  assert {
    condition     = aws_route.private_nat.route_table_id == "rtb-priv" && aws_route.private_nat.destination_cidr_block == "0.0.0.0/0"
    error_message = "10-base 의 private 라우팅 테이블에 NAT 기본 경로를 더한다"
  }

  assert {
    condition     = module.eks.node_groups["app"].subnet_ids == toset(["subnet-priv-a"]) && module.eks.node_groups["platform"].subnet_ids == toset(["subnet-priv-c"])
    error_message = "app 은 2a, platform 은 2c"
  }

  assert {
    condition     = module.eks.node_groups["app"].labels["role"] == "app" && one(module.eks.node_groups["platform"].taints) == "role=platform:NO_SCHEDULE"
    error_message = "노드그룹 이름이 라벨과 taint role=<이름> 이 된다"
  }

  assert {
    condition     = module.eks.addons == tolist(["aws-ebs-csi-driver", "coredns", "eks-pod-identity-agent", "kube-proxy", "vpc-cni"])
    error_message = "EKS 애드온 5개"
  }

  assert {
    condition     = keys(aws_eks_pod_identity_association.this) == ["ebs-csi", "loki"]
    error_message = "10-base 의 Pod Identity 표마다 연결"
  }
}
