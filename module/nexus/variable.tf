variable "name" {
  description = "Base name for nexus resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC id where nexus will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet ids where nexus can be placed"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name to attach to the instance (optional)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.medium"
}

variable "domain" {
  description = "Route53 zone domain (e.g. example.com)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain to create (e.g. nexus.example.com)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (optional)"
  type        = string
  default     = ""
}

variable "ssl_certificate_arn" {
  description = "Optional: ARN of an existing ACM certificate to use for the ELB. If empty, the module will request a certificate and validate via Route53."
  type        = string
  default     = ""
}

variable "newrelic_api_key" {
  description = "Optional New Relic license/API key for infrastructure agent"
  type        = string
  default     = ""
}

variable "newrelic_account_id" {
  description = "Optional New Relic account id"
  type        = string
  default     = ""
}

