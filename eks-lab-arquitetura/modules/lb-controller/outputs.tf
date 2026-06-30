output "role_arn" {
  description = "ARN da Role IRSA do Load Balancer Controller."
  value       = module.lb_controller_role.iam_role_arn
}

output "service_account_name" {
  description = "Nome do ServiceAccount do controller."
  value       = kubernetes_service_account.lbc.metadata[0].name
}
