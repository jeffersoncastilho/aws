# Stack 6/7 — Exposição (deployment + service + ingress/ALB).
# Depende de: eks, governanca, irsa e (em runtime) do lb-controller já instalado.
module "exposicao" {
  source = "../../modules/exposicao"

  app_name             = var.app_name
  namespace            = data.terraform_remote_state.governanca.outputs.namespace
  service_account_name = data.terraform_remote_state.irsa.outputs.service_account_name
}
