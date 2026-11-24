# AWS 에 접속하지 않는 plan. terraform init -backend=false && terraform test
mock_provider "aws" {}

variables {
  name            = "maemusae"
  region          = "ap-northeast-2"
  vpc_cidr        = "10.50.0.0/16"
  public_subnet   = { az = "ap-northeast-2a", cidr = "10.50.200.0/24" }
  private_subnets = { "ap-northeast-2a" = "10.50.0.0/20", "ap-northeast-2c" = "10.50.16.0/20" }
  db_subnets      = { "ap-northeast-2a" = "10.50.100.0/24", "ap-northeast-2c" = "10.50.101.0/24" }
}

# route 는 계산 값이라 plan 에서는 알 수 없다. mock provider 로 apply 한다
run "always_on_network" {
  command = apply

  assert {
    condition     = length(aws_route_table.private.route) == 0
    error_message = "private 라우팅 테이블에 기본 경로가 없다. NAT 경로는 20-eks 가 더한다"
  }

  assert {
    condition     = keys(aws_route_table_association.private) == ["ap-northeast-2a", "ap-northeast-2c"]
    error_message = "2a, 2c 프라이빗 서브넷이 private 라우팅 테이블 하나를 같이 쓴다"
  }

  assert {
    condition     = length(aws_route_table.db.route) == 0 && keys(aws_route_table_association.db) == ["ap-northeast-2a", "ap-northeast-2c"]
    error_message = "DB 서브넷 2a, 2c 는 기본 경로가 없는 db 라우팅 테이블을 쓴다"
  }

  assert {
    condition     = alltrue([for a in aws_route_table_association.db : a.route_table_id == aws_route_table.db.id && a.route_table_id != aws_route_table.private.id])
    error_message = "DB 서브넷은 NAT 경로가 붙는 private 라우팅 테이블에 묶이지 않는다"
  }

  assert {
    condition     = aws_subnet.public.tags["kubernetes.io/role/elb"] == "1" && aws_subnet.private["ap-northeast-2c"].tags["kubernetes.io/role/internal-elb"] == "1"
    error_message = "LB Controller 서브넷 태그"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_node.from_port == 5432 && aws_vpc_security_group_ingress_rule.rds_from_node.to_port == 5432
    error_message = "RDS 는 노드 보안 그룹에서 오는 5432 만 받는다"
  }
}
