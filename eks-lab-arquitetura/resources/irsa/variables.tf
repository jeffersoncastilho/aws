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

variable "app_service_account" {
  description = "ServiceAccount da app que assumirá a Role IRSA."
  type        = string
  default     = "demo"
}
