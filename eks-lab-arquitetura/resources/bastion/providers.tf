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
