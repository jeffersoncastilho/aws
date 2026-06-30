# Stack 3/7 — AWS Load Balancer Controller. Depende de: network, eks.
module "lb_controller" {
  source = "../../modules/lb-controller"

  cluster_name      = data.terraform_remote_state.eks.outputs.cluster_name
  region            = var.region
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
}
