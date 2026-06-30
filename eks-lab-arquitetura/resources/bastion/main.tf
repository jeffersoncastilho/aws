# Stack 7/7 — Bastion EC2 (SSM) + VPC endpoints SSM. Depende de: network, eks.
module "bastion" {
  source = "../../modules/bastion"

  name                      = "${var.cluster_name}-bastion"
  vpc_id                    = data.terraform_remote_state.network.outputs.vpc_id
  subnet_id                 = data.terraform_remote_state.network.outputs.private_subnet_ids[0]
  cluster_security_group_id = data.terraform_remote_state.eks.outputs.cluster_security_group_id
  instance_type             = var.instance_type

  # VPC endpoints de SSM (não depender do NAT para o canal de controle do SSM).
  create_ssm_endpoints = true
  vpc_cidr             = data.terraform_remote_state.network.outputs.vpc_cidr
  endpoint_subnet_ids  = data.terraform_remote_state.network.outputs.private_subnet_ids
}

# Dá à Role do bastion acesso administrativo ao cluster (EKS Access Entry).
resource "aws_eks_access_entry" "bastion" {
  cluster_name  = data.terraform_remote_state.eks.outputs.cluster_name
  principal_arn = module.bastion.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "bastion_admin" {
  cluster_name  = data.terraform_remote_state.eks.outputs.cluster_name
  principal_arn = module.bastion.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.bastion]
}
