output "vpc_id" {
  description = "ID da VPC criada."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (onde ficam os nós do EKS)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (onde o ALB do Ingress é criado)."
  value       = module.vpc.public_subnets
}
