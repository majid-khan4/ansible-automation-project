variable "newrelic_api_key" {
  description = "New Relic API key"
  type        = string
  default = ""  
}


variable "newrelic_account_id" {
  description = "New Relic account id (optional)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "The domain name for the project"
  type        = string
  default     = "majiktech.uk"
}

variable "s3_bucket" {
  description = "S3 bucket name for Ansible playbooks upload."
  type        = string
  default     = "m3ap-remote-state-1"
}