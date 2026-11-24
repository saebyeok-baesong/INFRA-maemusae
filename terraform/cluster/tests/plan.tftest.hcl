# AWS 에 접속하지 않는 plan. base 의 output 을 아래 값으로 흉내 낸다. terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/tester" }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::123456789012:user/tester" }
  }
}

mock_provider "helm" {}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      name                          = "maemusae"
      vpc_id                        = "vpc-0123"
      public_subnet_ids             = ["subnet-pub-a"]
      private_subnet_ids_by_az      = { "ap-northeast-2a" = "subnet-priv-a", "ap-northeast-2c" = "subnet-priv-c" }
      private_route_table_ids       = ["rtb-priv"]
      eks_clients_security_group_id = "sg-eks-clients"
      ebs_csi_role_arn              = "arn:aws:iam::123456789012:role/maemusae-ebs-csi"
      workload_identities = {
        loki = { namespace = "monitoring", service_account = "loki", role_arn = "arn:aws:iam::123456789012:role/maemusae-loki" }
      }
    }
  }
}

variables {
  aws_account_id = "123456789012"
  caller_cidr    = "203.0.113.10/32"
}

run "default_draft" {
  command = plan

  assert {
    condition     = module.eks.eks_managed_node_groups["app"] != null && module.eks.eks_managed_node_groups["platform"] != null
    error_message = "app, platform 노드그룹"
  }

  assert {
    condition     = aws_nat_gateway.this.subnet_id == "subnet-pub-a"
    error_message = "NAT 는 첫 퍼블릭 서브넷(2a)에 둔다"
  }

  assert {
    condition     = keys(aws_route.private_nat) == ["rtb-priv"]
    error_message = "base 의 private 라우팅 테이블마다 NAT 경로"
  }
}
