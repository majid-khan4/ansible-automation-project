variable "region" {
  default = "eu-west-2" # London region
}

#domain
variable "domain_name" {
  description = "This will be the domain name of the project"
  type        = string
  default     = "majiktech.uk"
}