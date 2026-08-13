# 🏛️ Laboratório de Arquitetura EKS (Terraform)

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%237B42BC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)

Infra base, em **módulos Terraform**, para estudar os pontos arquiteturais de um cluster EKS:

1. **Segurança e Identidade** → IRSA (IAM Roles for Service Accounts) sobre o OIDC provider do cluster.
2. **Exposição de Tráfego** → Service (ClusterIP) + Ingress + AWS Load Balancer Controller (ALB).
3. **Segregação e Governança** → Namespaces, ResourceQuota, LimitRange e Network Policies.

> A **execução** (`terraform apply`, `kubectl`, etc.) é feita por você. Aqui está só a base versionada.

> 📖 **Estudo complementar:** [Observabilidade em EKS — Prometheus & Dynatrace](docs/OBSERVABILIDADE-EKS.md) (conceitual, prep. de entrevista) · [Stack ADOT → AMP → Grafana](docs/OBSERVABILIDADE-STACK-ADOT-AMP.md) (guia prático em Terraform).

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
    ├── bastion/              # stack 7 — lê: network, eks
    └── demo-s3-writer/       # stack 8 — lê: network, eks, governanca
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
| 8 | `demo-s3-writer` | Bucket S3 + IRSA de **escrita** (prefixo) + app + Ingress + NetworkPolicy p/ ALB | **bastion** | `terraform -chdir=demo-s3-writer apply` |

> **Por que muda "de onde roda"?** A API do cluster é **privada**. Stacks 1–3 só
> mexem na AWS (rodam da sua máquina). Stacks 4–8 falam com a API do Kubernetes,
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
Só o bucket S3 precisa existir antes do `init`. O lock é **nativo do S3**
(`use_lockfile = true`), então **não precisa de tabela DynamoDB** (Terraform >= 1.10):
```bash
aws s3api create-bucket --bucket SEU-BUCKET-TFSTATE --region us-east-1
aws s3api put-bucket-versioning --bucket SEU-BUCKET-TFSTATE \
  --versioning-configuration Status=Enabled
```
Depois crie seu `backend.hcl` a partir do exemplo (ele é git-ignored, fica só
local) e exporte as variáveis comuns (valem para todos os stacks):
```bash
cp resources/backend.hcl.example resources/backend.hcl
# edite resources/backend.hcl com o nome do seu bucket
```
```bash
export TF_VAR_state_bucket="SEU-BUCKET-TFSTATE"
export TF_VAR_region="us-east-1"
```

> A partir daqui, **crie um recurso (stack) de cada vez**, na ordem.
> Todo `init` usa o backend compartilhado (`-backend-config=../backend.hcl`);
> a `key` do state já está fixada no `versions.tf` de cada stack.
> Em todos os passos abaixo, parta de dentro da pasta `resources/`:
> ```bash
> cd resources
> ```

### 1. Recurso `network` (VPC, subnets, NAT) — _da sua máquina_
```bash
terraform -chdir=network init -backend-config=../backend.hcl
terraform -chdir=network plan
terraform -chdir=network apply
```

### 2. Recurso `eks` (cluster privado, OIDC/IRSA, nós) — _da sua máquina_
```bash
terraform -chdir=eks init -backend-config=../backend.hcl
terraform -chdir=eks plan
terraform -chdir=eks apply        # ⏳ ~15 min
```

### 3. Recurso `bastion` (EC2 SSM + VPC endpoints SSM) — _da sua máquina_
```bash
terraform -chdir=bastion init -backend-config=../backend.hcl
terraform -chdir=bastion plan
terraform -chdir=bastion apply
```
> Este stack também gerencia as **preferências do Session Manager** (documento
> regional `SSM-SessionManagerRunShell`), deixando o `kmsKeyId` vazio por padrão
> (sem KMS). Isso evita o erro `Error calling KMS GenerateDataKey ... Key does
> not exist` que encerra a sessão quando o doc aponta para uma KMS key deletada.
>
> ⚠️ Se a conta **já tiver** esse documento (configurado pelo console ou lab
> anterior), o `apply` acusa `DocumentAlreadyExists`. Faça a reconciliação **uma
> vez**:
> ```bash
> terraform -chdir=bastion import \
>   'module.bastion.aws_ssm_document.session_prefs[0]' SSM-SessionManagerRunShell
> terraform -chdir=bastion apply   # corrige o kmsKeyId
> ```
> Para manter criptografia KMS, passe `session_kms_key_id` com uma key válida.

### 4. Acessar o cluster via bastion (a API é privada)
```bash
# Abre sessão SSM (sem SSH). Precisa do session-manager-plugin local.
$(terraform -chdir=bastion output -raw bastion_connect)

# Já DENTRO do bastion (kubectl/helm/aws-cli pré-instalados).
# Clone o repo aqui (ou via VPN) para rodar os próximos stacks:
aws eks update-kubeconfig --name lab-arquitetura --region us-east-1
kubectl get nodes
```
> ⚠️ Os passos 5–9 falam com a API do Kubernetes, então rodam **de dentro do
> bastion**. Lá também exporte `TF_VAR_state_bucket` e `TF_VAR_region`.

### 5. Recurso `lb-controller` (Ingress/ALB) — _do bastion_
```bash
terraform -chdir=lb-controller init -backend-config=../backend.hcl
terraform -chdir=lb-controller plan
terraform -chdir=lb-controller apply
```

### 6. Recurso `governanca` (namespace + quotas + netpol) — _do bastion_
```bash
terraform -chdir=governanca init -backend-config=../backend.hcl
terraform -chdir=governanca plan
terraform -chdir=governanca apply
```

### 7. Recurso `irsa` (Role IAM + ServiceAccount) — _do bastion_
```bash
terraform -chdir=irsa init -backend-config=../backend.hcl
terraform -chdir=irsa plan
terraform -chdir=irsa apply
```

### 8. Recurso `exposicao` (deployment + service + ingress) — _do bastion_
```bash
terraform -chdir=exposicao init -backend-config=../backend.hcl
terraform -chdir=exposicao plan
terraform -chdir=exposicao apply
terraform -chdir=exposicao output ingress_hostname   # DNS do ALB (~2 min)
```

### 9. Recurso `demo-s3-writer` (app que ESCREVE no S3 via IRSA) — _do bastion_
Demonstra o caminho completo **Internet → ALB → Pod (IRSA) → S3**, com permissão
de **escrita escopada** a um prefixo e uma **NetworkPolicy** liberando o ALB (sem
ela o `default-deny` da governança bloquearia o Ingress).
```bash
terraform -chdir=demo-s3-writer init -backend-config=../backend.hcl
terraform -chdir=demo-s3-writer plan
terraform -chdir=demo-s3-writer apply
terraform -chdir=demo-s3-writer output ingress_hostname   # DNS do ALB (~2 min)

# Testar a escrita usando a MESMA ServiceAccount (Pod descartável com AWS CLI):
BUCKET=$(terraform -chdir=demo-s3-writer output -raw bucket_name)
SA=$(terraform -chdir=demo-s3-writer output -raw service_account_name)
# --command é necessário: a imagem aws-cli tem 'aws' como entrypoint; sem ele o
# 'sh -c ...' viraria argumento do aws ("invalid choice 'sh'").
kubectl -n time-a run s3-test --rm -it --restart=Never \
  --overrides="{\"spec\":{\"serviceAccountName\":\"$SA\"}}" \
  --image=public.ecr.aws/aws-cli/aws-cli:latest \
  --command -- sh -c "echo ola > /tmp/f && aws s3 cp /tmp/f s3://$BUCKET/demo-app/f"   # ✅ permitido
# troque 'demo-app/f' por 'fora/f' -> AccessDenied (fora do prefixo demo-app/*)
```

### 10. Destruir — um de cada vez, em ORDEM INVERSA
```bash
terraform -chdir=demo-s3-writer destroy  # do bastion
terraform -chdir=exposicao    destroy   # do bastion
terraform -chdir=irsa         destroy   # do bastion
terraform -chdir=governanca   destroy   # do bastion
terraform -chdir=lb-controller destroy  # do bastion
terraform -chdir=bastion      destroy   # da sua máquina
terraform -chdir=eks          destroy   # da sua máquina
terraform -chdir=network      destroy   # da sua máquina
```

---

## ✅ Pré-requisitos

- AWS CLI v2 configurado
- Terraform >= 1.5
- `kubectl` e `helm`
- Bastion/VPN na VPC (por causa do endpoint privado)
