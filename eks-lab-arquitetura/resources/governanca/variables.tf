variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket S3 do state remoto."
  type        = string
}

variable "team_namespace" {
  description = "Namespace de exemplo para governança."
  type        = string
  default     = "time-a"
}
