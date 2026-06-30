data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/eks/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "governanca" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/governanca/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "irsa" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/irsa/terraform.tfstate"
    region = var.region
  }
}
