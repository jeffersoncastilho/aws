# 🛠️ Stack de Observabilidade (ADOT → AMP → Grafana) — Guia de Estudo

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%237B42BC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)

Guia **para estudar** como montaria uma stack de métricas real neste lab, seguindo o
mesmo padrão dos outros stacks (`module` em `modules/` + `resource stack` em
`resources/`, IRSA, `terraform_remote_state`). Complementa o
[guia conceitual](OBSERVABILIDADE-EKS.md).

> ⚠️ **Isto é material de estudo, não código aplicado.** Os blocos abaixo mostram
> *como seria* o stack `observabilidade/`; leia-os como um passo a passo comentado.
> Quando quiser executar de verdade, é só materializar os arquivos nos caminhos
> indicados e seguir a ordem de `apply` do [README principal](../README.md).

---

## 1. O que essa stack entrega e por quê

```
Pods (/metrics) + node-exporter + kube-state-metrics
        │  (scrape — modelo pull)
        ▼
ADOT Collector (DaemonSet no EKS)
        │  remote_write assinado com SigV4 (credenciais via IRSA, sem chave estática)
        ▼
Amazon Managed Service for Prometheus (AMP)   ← TSDB serverless, PromQL
        │
        ▼
Amazon Managed Grafana (AMG) / Grafana        ← dashboards
```

**Decisões de arquitetura (o "porquê" que cai em entrevista):**

| Decisão | Motivo |
|---|---|
| **ADOT** em vez de Prometheus server local | Padrão OTel, sem lock-in; a AWS suporta e já traz o exportador SigV4 para o AMP. |
| **AMP** (gerenciado) em vez de TSDB própria | Não operar HA/retenção/escala da TSDB — a parte pesada vira serverless. |
| **IRSA** no coletor | O `remote_write` autentica assumindo uma Role IAM; **nada de `AWS_ACCESS_KEY_ID`** no Pod. Mesmo pilar do [IRSA do README](../README.md#1️⃣-segurança-e-identidade--irsa). |
| **DaemonSet** | 1 coletor por nó (padrão de coleta). ⚠️ Não funciona em **Fargate** — lá vira sidecar. |

> Posição na ordem do lab: entra **depois** de `lb-controller` (precisa de cluster +
> IRSA prontos) e **roda do bastion** (a API do cluster é privada).

---

## 2. Recursos AWS envolvidos

| Recurso | Papel |
|---|---|
| `aws_prometheus_workspace` (AMP) | Endpoint `remote_write` + TSDB gerenciada. |
| IAM Role + Policy (IRSA) | Permite ao coletor `aps:RemoteWrite` no workspace. |
| ServiceAccount anotado | Liga o Pod do coletor à Role (`eks.amazonaws.com/role-arn`). |
| Helm release `adot` (ou `opentelemetry-collector`) | Sobe o DaemonSet do coletor. |
| (opcional) `aws_grafana_workspace` (AMG) | Visualização gerenciada com login SSO. |

---

## 3. O módulo — `modules/observabilidade/`

### 3.1 `main.tf`

```hcl
# =============================================================================
# Stack de métricas: ADOT (coletor OTel) -> AMP (Prometheus gerenciado).
#
# Cria:
#   1. Um workspace no Amazon Managed Service for Prometheus (AMP).
#   2. A Role IRSA que autoriza o coletor a fazer remote_write no workspace.
#   3. O ServiceAccount anotado + o Helm release do ADOT Collector (DaemonSet).
# =============================================================================

# 1) Workspace do AMP — a "TSDB serverless". O remote_write_endpoint sai daqui.
resource "aws_prometheus_workspace" "this" {
  alias = "${var.cluster_name}-amp"
}

# 2) Role IRSA. Reaproveita o submódulo oficial (como o lb-controller faz),
#    mas com uma policy inline mínima: só remote_write neste workspace.
module "adot_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-adot"

  # Privilégio mínimo: apenas escrever amostras NESTE workspace.
  role_policy_arns = {
    amp = aws_iam_policy.adot_remote_write.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_policy" "adot_remote_write" {
  name = "${var.cluster_name}-adot-remote-write"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["aps:RemoteWrite"]
      Resource = aws_prometheus_workspace.this.arn
    }]
  })
}

# 3) ServiceAccount anotado com o ARN da Role (o coração do IRSA).
resource "kubernetes_service_account" "adot" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = module.adot_role.iam_role_arn
    }
  }
}

# 4) Coletor ADOT como DaemonSet. Faz scrape local e remote_write (SigV4) ao AMP.
resource "helm_release" "adot" {
  name       = "adot-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = var.namespace
  version    = var.chart_version

  values = [yamlencode({
    mode = "daemonset"
    serviceAccount = {
      create = false
      name   = kubernetes_service_account.adot.metadata[0].name
    }
    config = {
      receivers = {
        # Descobre os targets via API do K8s e faz o scrape (modelo pull).
        prometheus = {
          config = {
            scrape_configs = [{
              job_name        = "kubernetes-pods"
              scrape_interval = "30s"
              kubernetes_sd_configs = [{ role = "pod" }]
            }]
          }
        }
      }
      exporters = {
        # Exportador que assina o remote_write com SigV4 usando as credenciais
        # temporárias que o IRSA injeta no Pod.
        prometheusremotewrite = {
          endpoint = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
          auth     = { authenticator = "sigv4auth" }
        }
      }
      extensions = {
        sigv4auth = { region = var.region }
      }
      service = {
        extensions = ["sigv4auth"]
        pipelines = {
          metrics = {
            receivers = ["prometheus"]
            exporters = ["prometheusremotewrite"]
          }
        }
      }
    }
  })]

  depends_on = [kubernetes_service_account.adot]
}
```

### 3.2 `variables.tf`

```hcl
variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "region" {
  description = "Região AWS."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC provider (output do módulo eks)."
  type        = string
}

variable "namespace" {
  description = "Namespace onde roda o coletor."
  type        = string
  default     = "observabilidade"
}

variable "service_account_name" {
  description = "Nome do ServiceAccount do coletor."
  type        = string
  default     = "adot-collector"
}

variable "chart_version" {
  description = "Versão do chart opentelemetry-collector."
  type        = string
  default     = "0.108.0"
}
```

### 3.3 `outputs.tf`

```hcl
output "amp_workspace_id" {
  description = "ID do workspace AMP."
  value       = aws_prometheus_workspace.this.id
}

output "amp_remote_write_endpoint" {
  description = "Endpoint de remote_write do AMP (para o coletor e para o Grafana)."
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "adot_role_arn" {
  description = "ARN da Role IRSA do coletor."
  value       = module.adot_role.iam_role_arn
}
```

### 3.4 `versions.tf`

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = ">= 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.20" }
    helm       = { source = "hashicorp/helm", version = ">= 2.12" }
  }
}
```

---

## 4. O resource stack — `resources/observabilidade/`

Segue exatamente o formato dos outros stacks: `remote.tf` lê os outputs de `eks`,
`providers.tf` autentica na API do cluster, `main.tf` chama o módulo.

### 4.1 `main.tf`

```hcl
# Stack observabilidade — ADOT + AMP. Depende de: eks (roda do bastion).
module "observabilidade" {
  source = "../../modules/observabilidade"

  cluster_name      = data.terraform_remote_state.eks.outputs.cluster_name
  region            = var.region
  oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
}
```

### 4.2 `remote.tf`

```hcl
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "eks-lab-arquitetura/eks/terraform.tfstate"
    region = var.region
  }
}
```

### 4.3 `versions.tf`

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
  }
  backend "s3" {
    key = "eks-lab-arquitetura/observabilidade/terraform.tfstate"
  }
}
```

### 4.4 `variables.tf` e `providers.tf`

Idênticos aos do stack `lb-controller` (mesmo `region` + `state_bucket`, e os
providers `kubernetes`/`helm` autenticando via `aws eks get-token`). Copie de
[`resources/lb-controller/`](../resources/lb-controller/).

---

## 5. Como rodaria (para fixar o fluxo)

```bash
# do BASTION (a API do cluster é privada), dentro de resources/
terraform -chdir=observabilidade init -backend-config=../backend.hcl
terraform -chdir=observabilidade plan
terraform -chdir=observabilidade apply

# endpoint do AMP para configurar como data source no Grafana:
terraform -chdir=observabilidade output amp_remote_write_endpoint
```

**Verificar que o coletor está escrevendo no AMP:**

```bash
kubectl -n observabilidade get pods          # DaemonSet: 1 pod por nó, Running
kubectl -n observabilidade logs ds/adot-collector | grep -i remote_write

# provar o IRSA (credencial temporária, sem chave estática):
kubectl -n observabilidade exec -it ds/adot-collector -- \
  sh -c 'aws sts get-caller-identity'   # deve mostrar assumed-role/<cluster>-adot/...
```

**Consultar no AMP via SigV4 (sem Grafana):**

```bash
WS=$(terraform -chdir=observabilidade output -raw amp_workspace_id)
awscurl --service aps --region us-east-1 \
  "https://aps-workspaces.us-east-1.amazonaws.com/workspaces/$WS/api/v1/query?query=up"
```

---

## 6. Onde os conceitos da entrevista aparecem neste stack

| Conceito do [guia conceitual](OBSERVABILIDADE-EKS.md) | Onde está no código |
|---|---|
| **Pull / scrape** | receiver `prometheus` + `kubernetes_sd_configs` (o coletor puxa). |
| **IRSA / privilégio mínimo** | `aws_iam_policy` só com `aps:RemoteWrite` no ARN do workspace. |
| **SigV4 sem chave estática** | extension `sigv4auth` + credencial temporária do IRSA. |
| **AMP serverless** | `aws_prometheus_workspace` (nenhum servidor para operar). |
| **DaemonSet como padrão de coleta** | `mode = "daemonset"` no chart. |
| **Fargate não tem DaemonSet** | por isso este lab usa Managed Node Group, não Fargate. |
| **OpenTelemetry como cola** | trocar o `exporters` leva as mesmas métricas para outro backend (ex.: Dynatrace via OTLP). |

---

## 7. Variação: exportar para o **Dynatrace** em vez do AMP

Só muda o **exportador** — a instrumentação e o receiver ficam iguais (a força do
OpenTelemetry). No `config.exporters` você troca `prometheusremotewrite` por:

```hcl
exporters = {
  otlphttp = {
    endpoint = "https://<seu-tenant>.live.dynatrace.com/api/v2/otlp"
    headers  = { Authorization = "Api-Token ${var.dynatrace_token}" }
  }
}
# ... e no pipeline: exporters = ["otlphttp"]
```

> **Frase de peso:** *"Instrumentei uma vez em OTel; escolher Prometheus/AMP ou
> Dynatrace virou trocar o bloco `exporters` — decisão de exportador, não de
> reescrita."*

---

## 📚 Ver também

- [Observabilidade em EKS — Prometheus & Dynatrace (conceitual)](OBSERVABILIDADE-EKS.md)
- [README principal do lab](../README.md)
- ADOT + AMP (AWS) — https://aws-otel.github.io/docs/getting-started/prometheus-remote-write-exporter
