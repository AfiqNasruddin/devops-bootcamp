terraform {
  required_version = ">= 1.15"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
  backend "s3" {
    bucket       = "bootcamp-2026-afiq"
    key          = "ansible2/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_caller_identity" "my_account" {}


