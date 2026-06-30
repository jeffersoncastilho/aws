output "role_arn" {
  description = "ARN da Role. Use no annotation do ServiceAccount: eks.amazonaws.com/role-arn"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Nome da Role criada."
  value       = aws_iam_role.this.name
}
