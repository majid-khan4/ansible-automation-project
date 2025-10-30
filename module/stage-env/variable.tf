variable "name" {}
variable "vpc_id" {}
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "bastion_sg" {}
variable "ansible_sg" {}
variable "domain_name" {}
variable "keypair" {}
variable "new_relic_api_key" {}
variable "new_relic_account_id" {}
