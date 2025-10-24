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
  vpc_cidr           = "10.0.0.0/16"
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
  source            = "./module/ansible"
  name              = local.name
  vpc_id            = module.vpc.vpc_id
  bastion_sg_id     = module.bastion.security_group_id
  private_subnet_id = module.vpc.private_subnet_ids[0]
  key_pair_name     = module.vpc.key_pair_name
  s3_bucket        = var.s3_bucket
}