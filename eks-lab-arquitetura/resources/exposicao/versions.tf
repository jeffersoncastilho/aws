terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
  backend "s3" {
    key = "eks-lab-arquitetura/exposicao/terraform.tfstate"
  }
}
