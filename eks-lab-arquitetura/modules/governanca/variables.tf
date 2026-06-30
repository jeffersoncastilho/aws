variable "namespace" {
  description = "Nome do namespace a criar/governar."
  type        = string
}

# ---- ResourceQuota (teto agregado do namespace) ----
variable "quota_requests_cpu" {
  type    = string
  default = "1"
}
variable "quota_requests_memory" {
  type    = string
  default = "2Gi"
}
variable "quota_limits_cpu" {
  type    = string
  default = "2"
}
variable "quota_limits_memory" {
  type    = string
  default = "4Gi"
}
variable "quota_pods" {
  type    = string
  default = "20"
}

# ---- LimitRange (default por container) ----
variable "limit_default_cpu" {
  type    = string
  default = "250m"
}
variable "limit_default_memory" {
  type    = string
  default = "256Mi"
}
variable "limit_default_request_cpu" {
  type    = string
  default = "100m"
}
variable "limit_default_request_memory" {
  type    = string
  default = "128Mi"
}
