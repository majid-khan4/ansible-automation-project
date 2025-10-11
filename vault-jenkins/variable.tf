// Variables for the vault-jenkins module
variable "aws_region" {
  description = "AWS region where the infrastructure will be deployed"
  type        = string
  default     = "eu-west-2"
}

variable "hosted_zone_name" {
  description = "The domain name registered in Route 53"
  type        = string
  default     = "majiktech.uk"
}

variable "jenkins_domain" {
  description = "The Jenkins subdomain"
  type        = string
  default     = "jenkins.majiktech.uk"
}