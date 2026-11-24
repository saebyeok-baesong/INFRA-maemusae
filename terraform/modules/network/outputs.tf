output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_ids_by_az" {
  value = { for az, s in aws_subnet.private : az => s.id }
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "nat_eip_allocation_id" {
  value = aws_eip.nat.allocation_id
}

output "nat_public_ip" {
  description = "외부 API 가 허용 IP 를 요구할 때 알려 줄 egress 주소"
  value       = aws_eip.nat.public_ip
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}
