# =============================================================================
# Stack 8 — demo-s3-writer. Depende de: network, eks, governanca e (em runtime)
# do lb-controller já instalado.
#
# Demonstra o caminho completo de uma app que ESCREVE no S3 via IRSA e é
# exposta pela internet via ALB, respeitando a governança do namespace:
#
#   Internet -> ALB (Ingress) -> Pod (SA com Role IAM) -> S3 (prefixo demo-app/*)
#
# Diferenças em relação aos stacks 'irsa' + 'exposicao' (que demonstram LEITURA):
#   - A IAM Policy é de ESCRITA, escopada a um único prefixo do bucket.
#   - Adiciona uma NetworkPolicy liberando o ALB — sem ela, o 'default-deny'
#     da governança bloquearia o tráfego de entrada do Ingress.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  namespace   = data.terraform_remote_state.governanca.outputs.namespace
  bucket_name = "${var.cluster_name}-demo-s3-writer-${data.aws_caller_identity.current.account_id}"
}

# -----------------------------------------------------------------------------
# Bucket S3 de destino da app (privado; force_destroy p/ limpeza fácil no lab).
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "app" {
  bucket        = local.bucket_name
  force_destroy = true # lab: permite destroy mesmo com objetos dentro
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Policy de ESCRITA escopada ao prefixo (least privilege):
#   - ListBucket só enxerga objetos sob 'demo-app/*'.
#   - Get/Put/DeleteObject apenas dentro de 'demo-app/*'.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "write" {
  statement {
    sid       = "ListBucketPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.app.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.write_prefix}/*"]
    }
  }

  statement {
    sid       = "ReadWriteObjectsPrefix"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.app.arn}/${var.write_prefix}/*"]
  }
}

# -----------------------------------------------------------------------------
# IRSA: Role que só o ServiceAccount desta app pode assumir (reusa o módulo).
# -----------------------------------------------------------------------------
module "irsa_app" {
  source = "../../modules/irsa-app"

  name                 = "${var.cluster_name}-${var.app_name}"
  oidc_provider_arn    = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  namespace            = local.namespace
  service_account_name = var.app_service_account
  policy_json          = data.aws_iam_policy_document.write.json
}

# ServiceAccount anotado com o ARN da Role (a "cola" entre o Pod e a Role IAM).
resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_service_account
    namespace = local.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_app.role_arn
    }
  }
}

# -----------------------------------------------------------------------------
# App de exemplo + Service + Ingress/ALB (reusa o módulo de exposição).
# -----------------------------------------------------------------------------
module "exposicao" {
  source = "../../modules/exposicao"

  app_name             = var.app_name
  namespace            = local.namespace
  service_account_name = kubernetes_service_account.app.metadata[0].name
  container_port       = var.container_port
}

# -----------------------------------------------------------------------------
# NetworkPolicy: libera a entrada do ALB nos Pods desta app.
#
# O ALB (target-type=ip) encaminha direto para o IP do Pod, mas a origem é a ENI
# do ALB — NÃO um Pod do namespace. Logo, o 'allow-same-namespace' da governança
# não cobre esse tráfego e o 'default-deny-ingress' bloquearia o Ingress.
# Liberamos a porta do container a partir do CIDR da VPC (onde vive o ALB).
# -----------------------------------------------------------------------------
resource "kubernetes_network_policy" "allow_alb" {
  metadata {
    name      = "allow-alb-${var.app_name}"
    namespace = local.namespace
  }
  spec {
    pod_selector {
      match_labels = {
        app = var.app_name
      }
    }
    policy_types = ["Ingress"]
    ingress {
      from {
        ip_block {
          cidr = data.terraform_remote_state.network.outputs.vpc_cidr
        }
      }
      ports {
        protocol = "TCP"
        port     = var.container_port
      }
    }
  }
}
