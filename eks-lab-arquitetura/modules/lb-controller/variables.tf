variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "region" {
  description = "Região AWS do cluster."
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC do cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider (output do módulo eks)."
  type        = string
}

variable "chart_version" {
  description = "Versão do chart Helm do aws-load-balancer-controller."
  type        = string
  default     = "1.8.1"
}
