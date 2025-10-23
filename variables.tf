variable "newrelic_api_key" {
  description = "New Relic API / license key for Infrastructure agent"
  type        = string
  sensitive   = true
  default     = ""
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