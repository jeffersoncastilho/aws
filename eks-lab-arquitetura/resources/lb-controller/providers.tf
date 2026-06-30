provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = "lab-arquitetura"
      environment = "lab"
      managed_by  = "terraform"
    }
  }
}

# Providers do cluster autenticam via 'aws eks get-token'. Como o endpoint é
# privado, rode este stack de dentro da VPC (bastion/VPN).
provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name, "--region", var.region]
    }
  }
}
