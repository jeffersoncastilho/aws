variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster será criado."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas para os nós do cluster."
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Expor a API do cluster na internet. Padrão false (somente privado)."
  type        = bool
  default     = false
}

variable "cluster_endpoint_private_access" {
  description = "Permitir acesso privado à API do cluster (dentro da VPC)."
  type        = bool
  default     = true
}

variable "node_instance_type" {
  description = "Tipo de instância dos nós."
  type        = string
  default     = "t3.medium"
}

variable "capacity_type" {
  description = "ON_DEMAND ou SPOT."
  type        = string
  default     = "SPOT"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nós."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nós."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Quantidade máxima de nós."
  type        = number
  default     = 4
}
