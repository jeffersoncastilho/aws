# =============================================================================
# Módulo de Exposição de Tráfego — aplicação de exemplo + Ingress (ALB).
#
# Caminho do tráfego:
#   Internet -> ALB (criado pelo Load Balancer Controller a partir do Ingress)
#            -> Service (ClusterIP) -> Pods do Deployment
#
# O Service é ClusterIP (interno). Quem expõe para a internet é o Ingress,
# traduzido em um ALB pelo controller. Em vez de um Service LoadBalancer por app
# (1 NLB cada), o Ingress permite um único ALB roteando por host/path (mais barato).
# =============================================================================

resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    labels = {
      app = var.app_name
    }
  }
  spec {
    replicas = var.replicas
    selector {
      match_labels = {
        app = var.app_name
      }
    }
    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }
      spec {
        # Define o ServiceAccount dos Pods — é por ele que o IRSA injeta as
        # credenciais temporárias da Role IAM.
        service_account_name = var.service_account_name

        container {
          name  = var.app_name
          image = var.image
          port {
            container_port = var.container_port
          }
          # requests/limits explícitos (o LimitRange cobriria, mas é boa prática declarar).
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "this" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
  }
  spec {
    type = "ClusterIP"
    selector = {
      app = var.app_name
    }
    port {
      port        = 80
      target_port = var.container_port
    }
  }
}

resource "kubernetes_ingress_v1" "this" {
  metadata {
    name      = var.app_name
    namespace = var.namespace
    annotations = {
      # 'internet-facing' => ALB público (nas subnets com tag kubernetes.io/role/elb).
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"
      # 'ip' encaminha direto para o IP dos Pods (modo recomendado com VPC CNI).
      "alb.ingress.kubernetes.io/target-type"  = "ip"
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\": 80}]"
    }
  }
  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.this.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
