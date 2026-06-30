output "namespace" {
  description = "Nome do namespace criado."
  value       = kubernetes_namespace.this.metadata[0].name
}
