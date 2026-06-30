output "role_arn" {
  value = module.irsa_app.role_arn
}

output "service_account_name" {
  value = kubernetes_service_account.demo.metadata[0].name
}
