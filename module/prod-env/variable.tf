variable "name" {}
variable "vpc_id" {}
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "bastion_sg_id" {}
variable "ansible_sg_id" {}
variable "domain_name" {}
variable "keypair" {}