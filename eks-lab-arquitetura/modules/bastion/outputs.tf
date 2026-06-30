output "instance_id" {
  description = "ID da instância do bastion."
  value       = aws_instance.this.id
}

output "iam_role_arn" {
  description = "ARN da Role do bastion (use numa EKS Access Entry para dar acesso ao cluster)."
  value       = aws_iam_role.this.arn
}

output "security_group_id" {
  description = "Security group do bastion."
  value       = aws_security_group.this.id
}
