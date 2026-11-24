module "network" {
  source = "../../../modules/network"

  name            = var.name
  region          = var.region
  vpc_cidr        = var.vpc_cidr
  public_subnet   = var.public_subnet
  private_subnets = var.private_subnets
  db_subnets      = var.db_subnets
}
