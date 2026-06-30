output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster (base64) para configurar os providers kubernetes/helm."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Security group gerenciado pelo cluster."
  value       = module.eks.cluster_security_group_id
}

# Saídas essenciais para o IRSA: o ARN e a URL do OIDC provider são usados
# para construir a trust policy das Roles assumidas pelos ServiceAccounts.
output "oidc_provider_arn" {
  description = "ARN do OIDC provider do cluster (usado nas Roles do IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "URL do OIDC provider (sem https://)."
  value       = module.eks.oidc_provider
}
