# Stack 5/7 — IRSA da app. Depende de: eks, governanca.
module "irsa_app" {
  source = "../../modules/irsa-app"

  name                 = "${var.cluster_name}-demo-app"
  oidc_provider_arn    = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  namespace            = data.terraform_remote_state.governanca.outputs.namespace
  service_account_name = var.app_service_account
}

# ServiceAccount anotado com o ARN da Role (a "cola" entre o Pod e a Role IAM).
resource "kubernetes_service_account" "demo" {
  metadata {
    name      = var.app_service_account
    namespace = data.terraform_remote_state.governanca.outputs.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_app.role_arn
    }
  }
}
