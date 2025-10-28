locals {
  name = "m3ap-main"
}

# data block to fetch route53 zone information
data "aws_route53_zone" "my-hosted-zone" {
  name         = var.domain_name
  private_zone = false
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
  private_key_pem     = module.vpc.private_key_pem
  newrelic_api_key    = var.newrelic_api_key
  newrelic_account_id = var.newrelic_account_id

}

module "nexus" {
  source             = "./module/nexus"
  name               = local.name
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  key_pair_name      = module.vpc.key_pair_name
  domain_name        = var.domain_name
  newrelic_api_key   = var.newrelic_api_key 
  newrelic_account_id = var.newrelic_account_id
}

module "sonarqube" {
  source             = "./module/sonarqube"
  name               = local.name
  vpc_id             = module.vpc.vpc_id 
  subnet_id          = module.vpc.public_subnet_ids[0]
  key_pair_name      = module.vpc.key_pair_name
  domain_name        = var.domain_name
  subnet_ids         = module.vpc.public_subnet_ids
  newrelic_api_key   = var.newrelic_api_key
  newrelic_account_id = var.newrelic_account_id
}

module "ansible" {
  source              = "./module/ansible"
  name                = local.name
  vpc_id              = module.vpc.vpc_id
  bastion_sg_id       = module.bastion.security_group_id
  private_subnet_id   = module.vpc.private_subnet_ids[0]
  key_pair_name       = module.vpc.key_pair_name
  s3_bucket           = var.s3_bucket
  private_key_pem     = module.vpc.private_key_pem
  nexus_ip            = module.nexus.public_ip
  newrelic_api_key    = var.newrelic_api_key
  newrelic_account_id = var.newrelic_account_id
}

module "stage-env" {
  source = "./module/stage-env"
  name = local.name
  vpc_id = module.vpc.vpc_id
  public_subnet_ids = [module.vpc.public_subnet_ids[0],module.vpc.public_subnet_ids[1]]
  private_subnet_ids = [module.vpc.private_subnet_ids[0],module.vpc.private_subnet_ids[1]]
  bastion_sg_id = module.bastion.security_group_id
  ansible_sg_id = module.ansible.security_group_id
  domain_name = var.domain_name
  keypair = module.vpc.key_pair_name
  new_relic_api_key = var.newrelic_api_key
  new_relic_account_id = var.newrelic_account_id
}

module "prod-env" {
  source              = "./module/prod-env"
  name                = local.name
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = [module.vpc.public_subnet_ids[0],module.vpc.public_subnet_ids[1]]
  private_subnet_ids  = [module.vpc.private_subnet_ids[0],module.vpc.private_subnet_ids[1]]
  bastion_sg_id       = module.bastion.security_group_id
  ansible_sg_id       = module.ansible.security_group_id
  domain_name         = var.domain_name
  keypair            = module.vpc.key_pair_name
  new_relic_api_key    = var.newrelic_api_key
  new_relic_account_id = var.newrelic_account_id
}

module "database" {
  source = "./module/databse"
  name = local.name
  vpc_id = module.vpc.vpc_id
  db_subnets = [module.vpc.private_subnet_ids[0], module.vpc.private_subnet_ids[1]]
  stage_sg = module.stage-env.stage_security_group_id
  prod_sg = module.prod-env.prod_security_group_id
  db_username = "admin"
  db_password = "admin123"
}