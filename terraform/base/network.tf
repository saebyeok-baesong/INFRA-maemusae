# NAT 는 노드가 떠 있을 때만 필요해서 cluster 층이 만들고 지운다. 이 층의 private 라우팅 테이블에 기본 경로를 더한다.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.azs

  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # single_nat_gateway 는 private 라우팅 테이블을 하나로 묶는 데만 쓴다. NAT 자체는 cluster 층에 있다
  enable_nat_gateway   = false
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # AWS Load Balancer Controller 가 이 태그로 NLB 를 둘 서브넷을 찾는다
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# EKS 노드는 매일 새로 생겨 노드 보안 그룹 ID 가 바뀐다. RDS 가 참조할 고정 그룹을 여기 두고 cluster 층이 노드에 붙인다
resource "aws_security_group" "eks_clients" {
  name        = "${var.name}-eks-clients"
  description = "Attached to EKS nodes. RDS allows ingress from this group"
  vpc_id      = module.vpc.vpc_id
}
