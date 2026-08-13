output "bucket_name" {
  description = "Bucket S3 onde a app escreve (prefixo permitido: <write_prefix>/*)."
  value       = aws_s3_bucket.app.id
}

output "write_prefix" {
  description = "Prefixo no bucket ao qual a permissão de escrita está escopada."
  value       = "${var.write_prefix}/"
}

output "role_arn" {
  description = "ARN da Role IRSA de escrita assumida pelos Pods."
  value       = module.irsa_app.role_arn
}

output "service_account_name" {
  value = kubernetes_service_account.app.metadata[0].name
}

output "ingress_hostname" {
  description = "DNS do ALB (pode levar ~2 min após o apply)."
  value       = module.exposicao.ingress_hostname
}
