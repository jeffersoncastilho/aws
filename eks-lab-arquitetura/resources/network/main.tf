# Stack 1/7 — Rede. Não depende de nenhum outro stack.
module "network" {
  source = "../../modules/network"

  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
}
