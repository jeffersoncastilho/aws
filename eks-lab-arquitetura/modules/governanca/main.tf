# =============================================================================
# Módulo de Governança / Segregação por Namespace.
#
# Cria um namespace isolado com:
#   - ResourceQuota : teto agregado de CPU/memória/objetos do namespace.
#   - LimitRange    : default e limite por container (evita Pod sem request/limit).
#   - NetworkPolicy : isolamento de rede (default-deny + permite tráfego interno).
# =============================================================================

resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
    labels = {
      "team"                         = var.namespace
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Teto total de recursos que TODOS os Pods do namespace podem consumir.
resource "kubernetes_resource_quota" "this" {
  metadata {
    name      = "quota"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"    = var.quota_requests_cpu
      "requests.memory" = var.quota_requests_memory
      "limits.cpu"      = var.quota_limits_cpu
      "limits.memory"   = var.quota_limits_memory
      "pods"            = var.quota_pods
    }
  }
}

# Valores default/limite POR container. Garante que todo Pod tenha request/limit
# (necessário, inclusive, para o ResourceQuota acima ser respeitado).
resource "kubernetes_limit_range" "this" {
  metadata {
    name      = "limits"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = var.limit_default_cpu
        memory = var.limit_default_memory
      }
      default_request = {
        cpu    = var.limit_default_request_cpu
        memory = var.limit_default_request_memory
      }
    }
  }
}

# 1) Default-deny: por padrão, nenhum Pod do namespace recebe tráfego de entrada.
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {} # aplica a todos os Pods do namespace
    policy_types = ["Ingress"]
    # sem regras 'ingress' => nega tudo
  }
}

# 2) Libera tráfego entre Pods do MESMO namespace (comunicação interna do time).
resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace.this.metadata[0].name
          }
        }
      }
    }
  }
}
