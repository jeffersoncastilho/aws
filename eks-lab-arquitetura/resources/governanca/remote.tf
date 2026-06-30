data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/eks/terraform.tfstate"
    region = var.region
  }
}
