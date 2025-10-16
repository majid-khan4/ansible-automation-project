# Provider block moved here so it's in the dedicated provider file.
provider "aws" {
  region  = "eu-west-2"
  profile = "my_account"
}

terraform {
  backend "s3" {
    bucket       = "m3ap-remote-state-1"
    key          = "vault-jenkins"
    encrypt      = true
    use_lockfile = true
    region       = "eu-west-2"
    profile      = "my_account"
  }
}