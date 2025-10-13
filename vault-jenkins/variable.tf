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

variable "aws_profile" {
  description = "AWS CLI profile name to use for provider (optional). If empty, provider will use default credentials chain."
  type        = string
  default     = "my_account"
}

variable "jenkins_port" {
  description = "Port on which Jenkins listens on the instance"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path ALB/ELB health check will use"
  type        = string
  default     = "/login"
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "nexus_registry" {
  description = "Optional Nexus registry URL (host:port or host) to configure Docker to pull/push images"
  type        = string
  default     = ""
}

variable "nexus_username" {
  description = "Optional Nexus registry username"
  type        = string
  default     = ""
}

variable "nexus_password" {
  description = "Optional Nexus registry password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "newrelic_license" {
  description = "New Relic Infrastructure license key (optional). If empty, New Relic agent won't be installed/configured."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_domain" {
  description = "FQDN for Vault (e.g. vault.example.com)"
  type        = string
  default     = "vault.majiktech.uk"
}

variable "vault_instance_type" {
  description = "EC2 instance type for Vault server"
  type        = string
  default     = "t2.medium"
}

variable "vault_version" {
  description = "Vault binary version to install in userdata"
  type        = string
  default     = "1.18.3"
}

variable "vault_root_token" {
  description = "Initial root token for dev Vault instance (for demo only). Provide a secure token in production via secure mechanisms."
  type        = string
  sensitive   = true
  default     = "root-token-demo"
}

variable "vault_db_username" {
  description = "Database username to store in Vault"
  type        = string
  default     = "dbuser"
}

variable "vault_db_password" {
  description = "Database password to store in Vault"
  type        = string
  sensitive   = true
  default     = "dbpass"
}

variable "vault_db_host" {
  description = "Database host to store in Vault"
  type        = string
  default     = "db.internal.local"
}

variable "vault_db_name" {
  description = "Database name to store in Vault"
  type        = string
  default     = "exampledb"
}