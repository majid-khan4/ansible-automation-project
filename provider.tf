provider "aws" {
  region = "eu-west-2"
    profile = "my_account"
}

terraform {
  # NOTE: Temporarily disabled backend for local validation/plan. Restore this block
  # when you want Terraform to use the S3 remote state.
  # backend "s3" {  
  #   bucket = "m3ap-remote-state-1"
  #   key = "infrastructure/terraform.tfstate"
  #   encrypt = true
  #   use_lockfile = true
  #   region = "eu-west-2"
  #   profile = "my_account"
  # }
} 
