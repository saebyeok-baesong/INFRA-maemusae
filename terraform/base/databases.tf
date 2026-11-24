resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "PostgreSQL from EKS nodes only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_clients.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name}-${each.key}"
  engine         = "postgres"
  engine_version = each.value.engine_version
  instance_class = each.value.instance_class
  db_name        = each.key

  allocated_storage = each.value.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  username = "maemusae"
  # 비밀번호를 RDS 가 Secrets Manager 에 만들고 회전한다. state 에 비밀번호가 남지 않는다
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = var.rds_backup_retention_days
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  deletion_protection        = var.rds_deletion_protection
  skip_final_snapshot        = false
  final_snapshot_identifier  = "${var.name}-${each.key}-final"
}
