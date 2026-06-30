# Stack 4/7 — Governança (namespace + quotas + netpol). Depende de: eks.
module "governanca" {
  source = "../../modules/governanca"

  namespace = var.team_namespace
}
