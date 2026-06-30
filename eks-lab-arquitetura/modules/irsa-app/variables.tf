variable "name" {
  description = "Nome base da Role/Policy do IRSA."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster (output do módulo eks)."
  type        = string
}

variable "namespace" {
  description = "Namespace do ServiceAccount que poderá assumir a Role."
  type        = string
}

variable "service_account_name" {
  description = "Nome do ServiceAccount que poderá assumir a Role."
  type        = string
}

variable "policy_json" {
  description = "JSON da IAM Policy da aplicação. Se null, usa o policy.json do módulo (leitura S3 de exemplo)."
  type        = string
  default     = null
}
