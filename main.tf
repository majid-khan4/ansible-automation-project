locals {
  name = "m3ap-main"
}

module "vpc" {
  source      = "./module/vpc"
  name        = local.name
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
}

module "bastion" {
  source = "./module/bastion-host"
  name   = "bastion"
  public_subnet_ids = module.vpc.public_subnet_ids
  vpc_id            = module.vpc.vpc_id
  key_pair_name     = module.vpc.key_pair_name

}