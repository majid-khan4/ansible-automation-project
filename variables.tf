variable "newrelic_api_key" {
  description = "New Relic API key"
  type        = string
  default     = "NRAK-RV61KHOC84AWAPUP24WCTQV9UY3"
}


variable "newrelic_account_id" {
  description = "New Relic account id (optional)"
  type        = string
  default     = "3947187"

}

variable "vault_token" {
  description = "Vault token for accessing secrets"
  type        = string
  default     = "hvs.vWbOFrII5Y8tQfQrwBJWqxZc"
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

variable "region" {
  default = "eu-west-2" # London region
}
