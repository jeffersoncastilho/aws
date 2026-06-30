# 🏛️ Laboratório de Arquitetura EKS (Terraform)

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%237B42BC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)

Infra base, em **módulos Terraform**, para estudar os pontos arquiteturais de um cluster EKS:

1. **Segurança e Identidade** → IRSA (IAM Roles for Service Accounts) sobre o OIDC provider do cluster.
2. **Exposição de Tráfego** → Service (ClusterIP) + Ingress + AWS Load Balancer Controller (ALB).
3. **Segregação e Governança** → Namespaces, ResourceQuota, LimitRange e Network Policies.

> A **execução** (`terraform apply`, `kubectl`, etc.) é feita por você. Aqui está só a base versionada.

---

## ⚠️ Custo (conta nova / free tier)

Este lab **NÃO cabe no free tier**. Cobram, independentemente do uso:

| Recurso | Custo aproximado |
|---|---|
| EKS Control Plane | ~US$ 0,10/h (~US$ 73/mês) |
| Nós EC2 (Spot t3.medium x2) | ~US$ 0,02–0,03/h |
| NAT Gateway (1x) | ~US$ 0,045/h + tráfego |
| ALB (Ingress) | ~US$ 0,0225/h + LCU |

**Defaults já otimizados para custo:** nós **Spot**, **1 NAT Gateway**, instâncias `t3.medium`.
👉 **Rode `terraform destroy` ao terminar os testes** para não acumular cobrança.

---

## 🗂️ Estrutura

```
eks-lab-arquitetura/
├── modules/                  # módulos reutilizáveis do Terraform
│   ├── network/              # VPC (subnets públicas p/ ALB, privadas p/ nós)
│   ├── eks/                  # cluster EKS + OIDC/IRSA habilitado
│   ├── irsa-app/             # Role IAM + trust policy OIDC (didático)
│   ├── lb-controller/        # IRSA + Helm do AWS Load Balancer Controller
│   ├── governanca/           # Namespace + ResourceQuota + LimitRange + NetworkPolicy
│   ├── exposicao/            # Deployment + Service ClusterIP + Ingress (ALB)
│   └── bastion/              # EC2 (SSM) + VPC endpoints SSM
└── resources/                # cada pasta = 1 STACK independente (state próprio)
    ├── backend.hcl           # config de backend S3 compartilhada (edite 1x)
    ├── terraform.tfvars.example
    ├── network/              # stack 1 — sem dependências
    ├── eks/                  # stack 2 — lê: network
    ├── lb-controller/        # stack 3 — lê: network, eks
    ├── governanca/           # stack 4 — lê: eks
    ├── irsa/                 # stack 5 — lê: eks, governanca
    ├── exposicao/            # stack 6 — lê: eks, governanca, irsa
    └── bastion/              # stack 7 — lê: network, eks
```

> Cada stack tem o próprio state no S3 (`key` diferente) e lê os outputs dos
> stacks anteriores via `terraform_remote_state`. Aplique-os **na ordem acima**.

---

## 🧭 Ordem de criação (o que criar, passo a passo)

Aplique **um stack por vez, nesta ordem**. Cada linha é uma pasta em `resources/`.

| # | Stack | O que cria | Roda de onde | Comando |
|---|---|---|---|---|
| 0 | _bootstrap_ | Bucket S3 + tabela DynamoDB do state | sua máquina | (ver Passo 0 abaixo) |
| 1 | `network` | VPC, subnets (pública p/ ALB, privada p/ nós), NAT | sua máquina | `terraform -chdir=network apply` |
| 2 | `eks` | Cluster EKS privado, OIDC/IRSA, nós Spot, add-ons | sua máquina | `terraform -chdir=eks apply` |
| 3 | `bastion` | EC2 (SSM) + VPC endpoints SSM + acesso ao cluster | sua máquina | `terraform -chdir=bastion apply` |
| 4 | `lb-controller` | IRSA + Helm do AWS Load Balancer Controller | **bastion** | `terraform -chdir=lb-controller apply` |
| 5 | `governanca` | Namespace + ResourceQuota + LimitRange + NetworkPolicy | **bastion** | `terraform -chdir=governanca apply` |
| 6 | `irsa` | Role IAM (trust OIDC) + ServiceAccount anotado | **bastion** | `terraform -chdir=irsa apply` |
| 7 | `exposicao` | Deployment + Service ClusterIP + Ingress (ALB) | **bastion** | `terraform -chdir=exposicao apply` |

> **Por que muda "de onde roda"?** A API do cluster é **privada**. Stacks 1–3 só
> mexem na AWS (rodam da sua máquina). Stacks 4–7 falam com a API do Kubernetes,
> então precisam rodar de **dentro da VPC** — pelo bastion (passos 3 e abaixo).
> Para destruir: **ordem inversa** (7 → 1).

---

## 🔒 Postura de rede: tudo privado, só o ALB exposto

- **API do cluster: privada** (`cluster_endpoint_public_access = false`).
- **Nós:** em subnets privadas.
- **Único ponto internet-facing:** o **ALB** criado pelo Ingress.

> Como a API é privada, `kubectl` e os providers `kubernetes`/`helm` do Terraform só
> conectam **de dentro da VPC**. Use um **bastion EC2** ou **VPN** na mesma VPC.
> (Para testes rápidos sem bastion, dá para subir com `cluster_endpoint_public_access = true`.)

---

## 1️⃣ Segurança e Identidade — IRSA

O `enable_irsa = true` (módulo `eks`) cria o **OIDC provider** do cluster e o associa à AWS.
A partir daí, um **ServiceAccount** consegue assumir uma **Role IAM** — sem `AWS_ACCESS_KEY_ID` estático.

Como a corrente se fecha neste lab:

```
ServiceAccount (annotation eks.amazonaws.com/role-arn)
        │
        ▼
IAM Role  ── trust policy ──►  OIDC provider do cluster
        │                         (condição: sub = system:serviceaccount:<ns>:<sa>)
        ▼
IAM Policy (permissões da app, ex.: leitura S3)
```

- O módulo **`irsa-app`** monta a **trust policy explicitamente** (ótimo para entender o `sub`/`aud`).
- O **`resources/main.tf`** cria o `ServiceAccount demo` anotado com o ARN da Role e o liga ao Deployment.

**Testar dentro de um Pod:**
```bash
kubectl -n time-a exec -it deploy/demo -- sh -c "aws sts get-caller-identity"
# Deve retornar o ARN da Role assumida (assumed-role/lab-arquitetura-demo-app-irsa/...)
```

---

## 2️⃣ Exposição de Tráfego — Service, Ingress e ALB

Caminho do pacote:
```
Internet ─► ALB ─► (Target Group: IPs dos Pods) ─► Service (ClusterIP) ─► Pods
            ▲
            └── criado pelo AWS Load Balancer Controller a partir do objeto Ingress
```

Tipos de Service (e por que usamos ClusterIP + Ingress):

| Tipo | O que faz | Uso |
|---|---|---|
| **ClusterIP** | IP interno do cluster | Comunicação interna; usado aqui, atrás do Ingress |
| **NodePort** | Abre uma porta em todos os nós | Raramente direto; base do LoadBalancer |
| **LoadBalancer** | Cria **1 NLB/CLB por Service** | Simples, mas caro se houver muitos serviços |
| **Ingress (+ALB)** | **1 ALB** roteando por host/path | Recomendado: consolida exposição L7 |

O módulo **`lb-controller`** instala o controller (via Helm) usando uma **Role IRSA** própria.
O módulo **`exposicao`** cria o `Ingress` com `ingressClassName: alb` e annotations `internet-facing` + `target-type: ip`.

```bash
kubectl -n time-a get ingress demo   # veja o ADDRESS (DNS do ALB)
terraform output demo_ingress_hostname
```

---

## 3️⃣ Segregação e Governança

O módulo **`governanca`** cria, por namespace:

- **ResourceQuota** — teto agregado de CPU/memória/Pods do namespace.
- **LimitRange** — request/limit **default por container** (evita Pod sem limites).
- **NetworkPolicy**:
  - `default-deny-ingress` — nega todo tráfego de entrada por padrão.
  - `allow-same-namespace` — libera comunicação entre Pods do mesmo namespace.

> As Network Policies são aplicadas pelo **VPC CNI** (habilitado com `enableNetworkPolicy=true`
> no add-on), que é a alternativa nativa ao **Calico** no EKS.

---

## 🚀 Como executar (você)

### 0. Bootstrap do backend (uma única vez)
O bucket/tabela do state precisam existir antes do `init`:
```bash
aws s3api create-bucket --bucket SEU-BUCKET-TFSTATE --region us-east-1
aws s3api put-bucket-versioning --bucket SEU-BUCKET-TFSTATE \
  --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region us-east-1
```
Depois edite `resources/backend.hcl` com o nome do bucket/tabela e exporte as
variáveis comuns (valem para todos os stacks):
```bash
export TF_VAR_state_bucket="SEU-BUCKET-TFSTATE"
export TF_VAR_region="us-east-1"
```

### 1. Apply de cada stack, NA ORDEM
Cada pasta em `resources/` é um stack independente. O `init` usa o backend
compartilhado (`-backend-config=../backend.hcl`); a `key` do state já está fixada
no `versions.tf` de cada stack.

```bash
cd resources

for stack in network eks; do
  terraform -chdir=$stack init -backend-config=../backend.hcl
  terraform -chdir=$stack apply
done
```
> ⏳ `network` + `eks` levam ~15 min. **Pare aqui e suba o bastion** para ter
> acesso de dentro da VPC (os próximos stacks tocam o cluster privado):

```bash
terraform -chdir=bastion init -backend-config=../backend.hcl
terraform -chdir=bastion apply
```

### 2. Acessar via bastion (endpoint é privado)
```bash
# Conecta no bastion via SSM (sem SSH). Precisa do session-manager-plugin local.
$(terraform -chdir=bastion output -raw bastion_connect)

# Já dentro do bastion (kubectl/helm/aws-cli pré-instalados):
aws eks update-kubeconfig --name lab-arquitetura --region us-east-1
kubectl get nodes
```

### 3. Stacks que tocam o cluster (rode de DENTRO do bastion)
Como a API é privada, os stacks `lb-controller`, `governanca`, `irsa` e
`exposicao` precisam ser aplicados de onde se alcança o endpoint — ex.: do
bastion (clone o repo lá ou use VPN). Ordem:
```bash
for stack in lb-controller governanca irsa exposicao; do
  terraform -chdir=$stack init -backend-config=../backend.hcl
  terraform -chdir=$stack apply
done
```

### 4. Destruir (faça isso!) — ordem INVERSA
```bash
for stack in exposicao irsa governanca lb-controller bastion eks network; do
  terraform -chdir=$stack destroy
done
```

---

## ✅ Pré-requisitos

- AWS CLI v2 configurado
- Terraform >= 1.5
- `kubectl` e `helm`
- Bastion/VPN na VPC (por causa do endpoint privado)
