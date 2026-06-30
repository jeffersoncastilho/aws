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

variable "cluster_version" {
  type    = string
  default = "1.30"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "capacity_type" {
  type    = string
  default = "SPOT"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "cluster_endpoint_public_access" {
  description = "Expor a API do cluster na internet. Padrão false (tudo privado)."
  type        = bool
  default     = false
}
