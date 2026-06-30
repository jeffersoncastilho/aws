variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket S3 do state remoto (mesmo de ../backend.hcl)."
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster (usado para nomear a VPC)."
  type        = string
  default     = "lab-arquitetura"
}

variable "vpc_cidr" {
  description = "CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Um único NAT Gateway (lab/barato) ou um por AZ (HA)."
  type        = bool
  default     = true
}
