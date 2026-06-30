# =============================================================================
# Módulo IRSA (IAM Roles for Service Accounts) — versão "didática".
#
# Cria, de forma explícita, a relação que permite um Pod assumir uma Role IAM:
#   1. Uma IAM Policy com as permissões da aplicação.
#   2. Uma IAM Role cuja TRUST POLICY confia no OIDC provider do cluster e
#      só libera para um ServiceAccount específico (namespace + nome).
#
# O Pod recebe credenciais temporárias via STS — sem AWS_ACCESS_KEY_ID estático.
# =============================================================================

data "aws_caller_identity" "current" {}

# O ARN do OIDC provider tem o formato:
#   arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<id>
# Extraímos a parte "oidc.eks.../id/<id>" para usar nas condições da trust policy.
locals {
  oidc_provider_url = replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")
}

# Trust policy: quem pode assumir esta Role.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # 'sub' amarra a Role a UM ServiceAccount específico (namespace:nome).
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    # 'aud' garante que o token foi emitido para o STS da AWS.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Permissões da aplicação. Por padrão usa o policy.json deste módulo (leitura S3),
# mas você pode injetar qualquer JSON via var.policy_json.
resource "aws_iam_policy" "this" {
  name   = "${var.name}-policy"
  policy = var.policy_json != null ? var.policy_json : file("${path.module}/policy.json")
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
