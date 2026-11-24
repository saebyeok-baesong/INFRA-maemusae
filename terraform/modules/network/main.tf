resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.name }
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  availability_zone = var.public_subnet.az
  cidr_block        = var.public_subnet.cidr

  # AWS Load Balancer Controller 가 이 태그로 인터넷용 NLB 를 둘 서브넷을 찾는다
  tags = {
    Name                     = "${var.name}-public-${var.public_subnet.az}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name                              = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.name }
}

# NAT Gateway 는 20-eks 가 코어타임에만 만든다. EIP 만 늘 남겨 외부 API 에 알려 줄 출구 IP 를 고정한다
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "${var.name}-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 기본 경로(0.0.0.0/0 -> NAT)는 20-eks 가 NAT 와 함께 더하고 지운다
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-private" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.name}-s3" }
}

# EKS 노드 보안 그룹. 클러스터는 매일 새로 만들지만 RDS 가 이 그룹 ID 를 참조해야 해서 늘 켜 두는 층에 둔다.
# kubernetes.io/cluster 태그를 달지 않는다. LB Controller 는 그 태그가 붙은 EKS 클러스터 보안 그룹에 NLB 규칙을 넣는다.
resource "aws_security_group" "node" {
  name        = "${var.name}-eks-node"
  description = "EKS nodes. Attached to every node group by the 20-eks layer"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-eks-node" }
}

resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "node to node"
}

resource "aws_vpc_security_group_ingress_rule" "node_from_public" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = var.public_subnet.cidr
  ip_protocol       = "tcp"
  from_port         = 0
  to_port           = 65535
  description       = "NLB health checks from the public subnet"
}

resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "PostgreSQL from EKS nodes only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_node" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes"
}
