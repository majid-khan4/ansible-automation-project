variable "name" {}

variable "vpc_id" {}

variable "bastion_sg_id" {}

variable "private_subnet_id" {}

variable "key_pair_name" {}

variable "s3_bucket" {}

variable "private_key_pem" {
  description = "Private key in PEM format for SSH access"
  type        = string
  sensitive   = true
}

variable "nexus_ip" {
  description = "IP address of the Nexus server"
  type        = string
}

variable "newrelic_api_key" {
  description = "API key for New Relic integration"
  type        = string
  sensitive   = true
}

variable "newrelic_account_id" {
  description = "Account ID for New Relic integration"
  type        = string
}