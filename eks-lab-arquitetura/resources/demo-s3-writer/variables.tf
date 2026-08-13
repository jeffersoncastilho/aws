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

variable "app_name" {
  description = "Nome da app de exemplo (Deployment/Service/Ingress)."
  type        = string
  default     = "s3-writer"
}

variable "app_service_account" {
  description = "ServiceAccount da app que assumirá a Role IRSA de escrita."
  type        = string
  default     = "s3-writer"
}

variable "container_port" {
  description = "Porta do container servida pelo ALB (deve casar com a do módulo exposicao)."
  type        = number
  default     = 80
}

variable "write_prefix" {
  description = "Prefixo no bucket onde a app pode escrever/ler. A permissão IAM é escopada a ele."
  type        = string
  default     = "demo-app"
}
