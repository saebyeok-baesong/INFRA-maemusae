# AWS 에 접속하지 않는 plan. 10-base, 20-eks 의 output 을 아래 값으로 흉내 낸다. terraform init -backend=false && terraform test
mock_provider "helm" {}

override_data {
  target = data.terraform_remote_state.eks
  values = {
    outputs = {
      cluster_name                       = "maemusae"
      cluster_endpoint                   = "https://example.eks.amazonaws.com"
      cluster_certificate_authority_data = "Y2E="
    }
  }
}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      region          = "ap-northeast-2"
      vpc_id          = "vpc-0123"
      route53_zone_id = ""
      pod_identities = {
        aws-load-balancer-controller = { namespace = "kube-system", service_account = "aws-load-balancer-controller", role_arn = "arn:aws:iam::123456789012:role/maemusae-aws-load-balancer-controller" }
        external-secrets             = { namespace = "external-secrets", service_account = "external-secrets", role_arn = "arn:aws:iam::123456789012:role/maemusae-external-secrets" }
      }
    }
  }
}

variables {
  aws_account_id = "123456789012"
}

run "no_domain" {
  command = plan

  assert {
    condition     = module.platform.releases == tolist(["argocd", "aws-load-balancer-controller", "external-secrets"])
    error_message = "도메인이 없으면 ExternalDNS 를 설치하지 않는다"
  }
}

run "with_domain" {
  command = plan

  override_data {
    target = data.terraform_remote_state.base
    values = {
      outputs = {
        region          = "ap-northeast-2"
        vpc_id          = "vpc-0123"
        route53_zone_id = "Z0000000000000"
        pod_identities = {
          aws-load-balancer-controller = { namespace = "kube-system", service_account = "aws-load-balancer-controller", role_arn = "arn:aws:iam::123456789012:role/maemusae-aws-load-balancer-controller" }
          external-secrets             = { namespace = "external-secrets", service_account = "external-secrets", role_arn = "arn:aws:iam::123456789012:role/maemusae-external-secrets" }
          external-dns                 = { namespace = "external-dns", service_account = "external-dns", role_arn = "arn:aws:iam::123456789012:role/maemusae-external-dns" }
        }
      }
    }
  }

  assert {
    condition     = module.platform.releases == tolist(["argocd", "aws-load-balancer-controller", "external-dns", "external-secrets"])
    error_message = "Route53 영역이 있으면 ExternalDNS 를 설치한다"
  }
}
