# Stack 2/7 — Cluster EKS. Depende de: network.
module "eks" {
  source = "../../modules/eks"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  node_instance_type             = var.node_instance_type
  capacity_type                  = var.capacity_type
  node_desired_size              = var.node_desired_size
  node_min_size                  = var.node_min_size
  node_max_size                  = var.node_max_size
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
}
