terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend parcial: bucket/region/lock vêm de ../backend.hcl no init.
  backend "s3" {
    key = "eks-lab-arquitetura/network/terraform.tfstate"
  }
}
