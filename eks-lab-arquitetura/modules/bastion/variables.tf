variable "name" {
  description = "Nome base do bastion (instância, role, SG)."
  type        = string
  default     = "eks-bastion"
}

variable "vpc_id" {
  description = "ID da VPC."
  type        = string
}

variable "subnet_id" {
  description = "Subnet (privada) onde o bastion será criado."
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group do cluster EKS, para liberar acesso à API privada (443)."
  type        = string
}

variable "instance_type" {
  description = "Tipo da instância do bastion."
  type        = string
  default     = "t3.micro"
}

variable "create_ssm_endpoints" {
  description = "Criar VPC endpoints de SSM (ssm, ssmmessages, ec2messages) para o SSM funcionar sem depender do NAT."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR da VPC (libera 443 nos endpoints de interface). Só usado se create_ssm_endpoints = true."
  type        = string
  default     = null
}

variable "endpoint_subnet_ids" {
  description = "Subnets (privadas) onde os VPC endpoints de interface serão criados. Só usado se create_ssm_endpoints = true."
  type        = list(string)
  default     = []
}

variable "manage_session_manager_prefs" {
  description = "Gerenciar o documento regional SSM-SessionManagerRunShell (preferências do Session Manager). Garante que o kmsKeyId seja válido e evita o erro 'Key does not exist' ao conectar."
  type        = bool
  default     = true
}

variable "session_kms_key_id" {
  description = "KMS key id/ARN para criptografar as sessões do Session Manager. Vazio = sem KMS (padrão do lab, mais simples/barato)."
  type        = string
  default     = ""
}
