variable "app_name" {
  description = "Nome da aplicação (Deployment/Service/Ingress)."
  type        = string
  default     = "demo"
}

variable "namespace" {
  description = "Namespace onde a aplicação será criada."
  type        = string
}

variable "image" {
  description = "Imagem do container."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:latest"
}

variable "container_port" {
  description = "Porta exposta pelo container."
  type        = number
  default     = 80
}

variable "replicas" {
  description = "Número de réplicas do Deployment."
  type        = number
  default     = 2
}

variable "service_account_name" {
  description = "ServiceAccount usado pelos Pods (para IRSA). Se null, usa o 'default' do namespace."
  type        = string
  default     = null
}
