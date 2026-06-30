output "service_name" {
  value = module.exposicao.service_name
}

output "ingress_hostname" {
  description = "DNS do ALB (pode levar ~2 min após o apply)."
  value       = module.exposicao.ingress_hostname
}
