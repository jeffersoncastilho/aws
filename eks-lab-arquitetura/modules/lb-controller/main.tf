# =============================================================================
# AWS Load Balancer Controller.
#
# É o controller que, ao ver um objeto Ingress, provisiona um ALB na AWS e
# direciona o tráfego da internet -> ALB -> Service -> Pods.
#
# Este módulo cria:
#   1. A Role IRSA com a política oficial do controller (via submódulo da AWS).
#   2. O ServiceAccount em kube-system anotado com o ARN da Role.
#   3. O Helm release do controller.
# =============================================================================

# Role IRSA usando o submódulo oficial, que já anexa a política gigante do
# controller (attach_load_balancer_controller_policy) — evita copiar ~200 linhas.
module "lb_controller_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "lbc" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"       = "aws-load-balancer-controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
    # Annotation que liga o ServiceAccount à Role IAM (coração do IRSA).
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lb_controller_role.iam_role_arn
    }
  }
}

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.chart_version

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
  # Reaproveita o ServiceAccount que já criamos (com o annotation do IRSA).
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.lbc.metadata[0].name
  }

  depends_on = [kubernetes_service_account.lbc]
}
