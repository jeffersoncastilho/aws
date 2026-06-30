output "service_name" {
  description = "Nome do Service ClusterIP."
  value       = kubernetes_service.this.metadata[0].name
}

output "ingress_hostname" {
  description = "DNS do ALB provisionado pelo Ingress (pode levar ~2 min para popular)."
  value       = try(kubernetes_ingress_v1.this.status[0].load_balancer[0].ingress[0].hostname, null)
}
