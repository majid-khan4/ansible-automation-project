provider "aws" {
  region = "eu-west-2"
    # profile = "personal_account"
}

provider "vault" {
  token = "hvs.jmnPPXIlXjb2G0f2bawpEohg"
  address = "https://vault.majiktech.uk"
}

data "vault_generic_secret" "database" {
  path = "secret/database"
}

terraform {
  # NOTE: Temporarily disabled backend for local validation/plan. Restore this block
  # when you want Terraform to use the S3 remote state.
  backend "s3" {  
    bucket = "m3ap-remote-state-1"
    key = "infrastructure/terraform.tfstate"
    encrypt = true
    use_lockfile = true
    region = "eu-west-2"
    # profile = "personal_account"
  }
}