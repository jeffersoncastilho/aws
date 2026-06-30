variable "cluster_name" {
  description = "Nome do cluster (usado para nomear a VPC e recursos)."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Quantidade de Availability Zones a utilizar."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "true usa um único NAT Gateway (mais barato); false cria um por AZ (HA)."
  type        = bool
  default     = true
}
