variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket S3 do state remoto."
  type        = string
}

variable "cluster_name" {
  type    = string
  default = "lab-arquitetura"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
