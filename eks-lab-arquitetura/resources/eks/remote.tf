# Lê os outputs do stack 'network'.
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/network/terraform.tfstate"
    region = var.region
  }
}
