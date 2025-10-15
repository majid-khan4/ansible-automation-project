variable "name" {
  type    = string
  default = "bastion"
}

variable "public_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids must contain at least one subnet id"
  }
}

variable "vpc_id" {
  type = string
  default = ""
}

variable "key_pair_name" {
  type = string
  default = ""
}

variable "region" {
  type    = string
  default = "eu-west-2"
}

