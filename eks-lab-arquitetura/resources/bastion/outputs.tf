output "instance_id" {
  value = module.bastion.instance_id
}

output "bastion_connect" {
  description = "Comando para conectar no bastion via SSM Session Manager."
  value       = "aws ssm start-session --target ${module.bastion.instance_id} --region ${var.region}"
}
