# 🎯 Entrevista de Arquitetura — Amazon EKS

> Guia conceitual de preparação. Quando a entrevista de Kubernetes afunila para o
> ecossistema AWS, o foco deixa de ser **"como o Kubernetes funciona"** e passa a
> ser **"como o Kubernetes escala, se comunica e se protege dentro da AWS"** —
> integrando conceitos nativos do K8s com os primitivos de infraestrutura da AWS.

## Índice

1. [Data Plane: gerenciamento de nós e escalonamento](#1-data-plane-gerenciamento-de-nós-e-escalonamento)
2. [Rede e exposição de serviços](#2-rede-e-exposição-de-serviços)
3. [Segurança e autenticação (IAM + K8s)](#3-segurança-e-autenticação-iam--k8s)
4. [Persistência de dados e armazenamento](#4-persistência-de-dados-e-armazenamento)
5. [Observabilidade nativa](#5-observabilidade-nativa)
6. [Cenário de arquitetura (picos de tráfego)](#-cenário-de-arquitetura-picos-de-tráfego)

---

## 1. Data Plane: gerenciamento de nós e escalonamento

O **Control Plane do EKS é gerenciado pela AWS** — você não administra os
`api-server`, `etcd` ou `scheduler`. As perguntas, portanto, focam em como você
desenha e escala os **Worker Nodes** (Data Plane).

### Tipos de compute — quando usar cada um

| Opção | Quem gerencia | Quando usar | Limitações |
|---|---|---|---|
| **Managed Node Groups** | AWS gerencia provisionamento, atualização de AMI e *draining* | Padrão para a maioria das cargas | Menos controle sobre o SO/kubelet |
| **Self-Managed Nodes** | Você gerencia a AMI e o `kubelet` | Customização pesada de SO, cenários híbridos ou muito específicos | Toda a operação (patch, upgrade) é sua |
| **AWS Fargate** | Serverless — sem nós para gerenciar | Cargas isoladas, *bursty* ou sem necessidade de DaemonSets | **Sem DaemonSets**, boot ligeiramente mais lento, custo fixo por vCPU/memória |

### Autoscaling: Karpenter vs. Cluster Autoscaler

**Pergunta clássica:** *Por que escolher o Karpenter em vez do Cluster Autoscaler tradicional?*

**Resposta de peso:** o **Cluster Autoscaler** opera sobre **Auto Scaling Groups
(ASG)** pré-definidos — ele só consegue subir/descer nós de tipos que você já
declarou nos ASGs. O **Karpenter** conversa **diretamente com a API do EC2**,
ignorando a camada de ASG:

1. Observa os **Pods `unschedulable`**.
2. Avalia os requisitos reais (CPU, memória, arquitetura, AZ, *taints/tolerations*).
3. Provisiona **o tipo exato de instância EC2 ideal** para aquela carga, **em segundos**.

Resultado: escala mais rápida, *bin-packing* melhor e otimização de custo
(escolhe a família/tamanho mais barato que atende, mistura Spot/On-Demand,
consolida nós subutilizados).

> **📌 Cenário:** uma fila de processamento de vídeo dispara 40 Pods de uma vez,
> cada um pedindo 8 vCPU e 16 GB. Com **Cluster Autoscaler**, o ASG só tem
> `m5.large` — ele subiria dezenas de nós pequenos e ainda deixaria Pods
> `Pending` por falta de CPU contígua. Com **Karpenter**, o controlador lê os
> *requests* dos 40 Pods, calcula que **duas `c6i.16xlarge` Spot** acomodam tudo
> com melhor *bin-packing*, e as provisiona em ~40s. Terminada a fila, a
> consolidação derruba os nós automaticamente.

---

## 2. Rede e exposição de serviços

A rede do EKS é particular por causa do **CNI padrão**.

### Amazon VPC CNI

Diferente de overlays como **Calico** ou **Flannel**, o **VPC CNI atribui um IP
real da VPC para cada Pod**. Vantagem: o Pod é um cidadão de primeira classe na
rede AWS (Security Groups, roteamento, ALB target-type IP).

**Desafio de produção — IP Exhaustion:** como cada Pod consome um IP da subnet,
subnets pequenas (`/24` ≈ 251 IPs úteis) **esgotam rápido**. Soluções:

- **Custom Networking** — associa **CIDRs secundários** (ex.: `100.64.0.0/16`,
  não-roteáveis) à VPC e coloca os Pods nesses ranges, preservando os IPs
  roteáveis para os nós.
- **IP Prefix Delegation** — em vez de IPs avulsos, o nó recebe **prefixos `/28`**
  (16 IPs por bloco), aumentando drasticamente a densidade de Pods por nó.

### AWS Load Balancer Controller

Substitui o mecanismo antigo (in-tree) que gerava ELBs clássicos. Ele traduz:

- Objetos **`Ingress`** → **Application Load Balancer (ALB)** — roteamento L7 por host/path.
- **`Service type: LoadBalancer`** → **Network Load Balancer (NLB)** — L4.

**Target Type IP** (config crucial): o ALB roteia **direto para o IP do Pod**
(graças ao VPC CNI), **pulando a camada de NodePort** e o salto extra via
`kube-proxy` — menos latência e *health checks* mais precisos.

> `alb.ingress.kubernetes.io/target-type: ip` — vale a pena ter na ponta da língua.

> **📌 Cenário:** um cluster foi criado em subnets `/24` (≈251 IPs). Em produção,
> um `HorizontalPodAutoscaler` escala de 30 para 300 Pods num pico de Black
> Friday. Como o **VPC CNI dá um IP da subnet por Pod**, os IPs acabam na metade
> do caminho: novos Pods ficam `ContainerCreating` com erro
> `failed to assign an IP address to container`. A correção sem recriar a rede:
> ativar **IP Prefix Delegation** — cada nó passa a alocar blocos `/28` (16 IPs
> por vez), multiplicando a densidade de Pods e absorvendo o pico. Se a subnet
> ainda fosse pequena demais, o próximo passo seria **Custom Networking**
> colocando os Pods num CIDR secundário `100.64.0.0/16`.

---

## 3. Segurança e autenticação (IAM + K8s)

**Nunca** use chaves estáticas (`AWS_ACCESS_KEY_ID`) dentro de containers. A
cobrança aqui é sobre **privilégio mínimo**.

### EKS Pod Identities vs. IRSA

Ambos associam uma **Role do IAM a uma ServiceAccount** do K8s para a aplicação
acessar recursos AWS (S3, DynamoDB, etc.) **sem credenciais estáticas**.

| Aspecto | IRSA (IAM Roles for Service Accounts) | EKS Pod Identities (evolução) |
|---|---|---|
| Mecanismo | **OIDC provider por cluster** + trust policy | **Agente/add-on** no cluster (EKS Pod Identity Agent) |
| Setup | Precisa mapear/registrar o OIDC de cada cluster | Mais simples; **sem OIDC por cluster** |
| Reuso de Roles | Trust policy amarrada ao OIDC específico | **Roles globais** reutilizáveis entre clusters |
| Performance/gestão | Boa | **Melhor** — associação nativa, mais simples de operar |

> **Fale isto na entrevista:** "IRSA continua amplamente usado, mas **EKS Pod
> Identities** é a abordagem moderna recomendada pela AWS — dispensa o mapeamento
> de OIDC por cluster e facilita Roles reutilizáveis." Demonstra que você está
> atualizado.

### Segurança de rede em duas camadas

- **Network Policies (K8s)** — regras L3/L4 nativas do Kubernetes.
- **Security Groups for Pods (AWS)** — atribui um **Security Group do EC2 a um
  Pod específico**, controlando tráfego no nível da infraestrutura AWS. Útil
  quando o Pod precisa falar com um RDS/serviço que filtra por SG.

> **📌 Cenário:** um microsserviço de pagamentos precisa ler de um bucket S3 e
> conectar num RDS PostgreSQL restrito por Security Group. **Sem chaves
> estáticas:** cria-se uma **ServiceAccount** anotada com o ARN de uma Role IAM
> (via **EKS Pod Identity** ou IRSA) cuja policy só permite `s3:GetObject` naquele
> bucket — o Pod assume a Role automaticamente e um `aws sts get-caller-identity`
> lá dentro retorna o ARN da Role, não credenciais de nó. **Para o RDS**, um
> **SecurityGroupPolicy** amarra um SG do EC2 àquele Pod, e a regra de entrada do
> RDS libera *apenas* esse SG — mesmo outro Pod no mesmo nó não alcança o banco.
> As duas camadas (IAM para dados, SG para rede) se somam ao `default-deny` das
> Network Policies.

---

## 4. Persistência de dados e armazenamento

Estado é mantido via **CSI (Container Storage Interface) Drivers**.

| Driver | Tipo de acesso | Uso típico | Escopo |
|---|---|---|---|
| **Amazon EBS CSI** | Bloco — **ReadWriteOnce (RWO)** | Bancos de dados em **StatefulSets** | **1 AZ** (volume preso à AZ) |
| **Amazon EFS CSI** | Arquivos — **ReadWriteMany (RWX)** | Mídia, logs centralizados, conteúdo compartilhado | **Multi-AZ** (vários Pods, várias AZs, simultâneo) |

**Pegadinha de arquitetura:** um volume **EBS vive em uma única AZ**. Se o Pod de
um StatefulSet for reagendado em outra AZ, ele **não consegue anexar** o mesmo
EBS. Mitigações: restringir o Pod à AZ do volume (topology-aware), ou usar EFS
para cargas RWX genuinamente multi-AZ. (Ver o cenário abaixo.)

> **📌 Cenário:** um Postgres roda como StatefulSet com um PVC EBS `gp3` na
> `us-east-1a`. O nó dessa AZ morre; o scheduler tenta recriar o Pod na
> `us-east-1b`, mas o volume **não anexa** — o Pod fica `Pending` com
> `volume node affinity conflict`. **Correção correta:** o `StorageClass` usa
> `volumeBindingMode: WaitForFirstConsumer`, então o volume só é criado *depois*
> que o Pod é agendado, na mesma AZ dele — e o EBS CSI adiciona um `nodeAffinity`
> de zona que mantém o Pod colado à AZ do volume. Para um CMS que precisa que
> **vários Pods em AZs diferentes escrevam no mesmo diretório** (ReadWriteMany),
> EBS não serve: troca-se para **EFS CSI**, que é multi-AZ nativo.

---

## 5. Observabilidade nativa

| Ferramenta | O que faz |
|---|---|
| **CloudWatch Container Insights** | Coleta **métricas de performance e logs** de infraestrutura de forma automatizada |
| **AWS Distro for OpenTelemetry (ADOT)** | Padrão de mercado para **métricas e traces sem vendor lock-in**; integra com **Amazon Managed Prometheus (AMP)** + **Grafana** ou terceiros (Datadog) |

> Argumento a favor do ADOT: **OpenTelemetry** evita *lock-in* — a mesma
> instrumentação exporta para AMP/Grafana hoje e para outra ferramenta amanhã,
> sem reinstrumentar a aplicação.

> **📌 Cenário:** a latência de checkout subiu e ninguém sabe se é a app, o banco
> ou a rede. O **Container Insights** já mostra que CPU e memória dos nós estão
> saudáveis — descarta infraestrutura. Aí entra o **ADOT como DaemonSet**:
> coleta métricas (RPS, p99) e as exporta para o **Amazon Managed Prometheus**,
> enquanto os **traces** (via OpenTelemetry) vão para o X-Ray/Grafana Tempo. No
> **Grafana** o trace distribuído revela que 300 ms são gastos numa query N+1 no
> serviço de estoque. Se amanhã a empresa adotar Datadog, só muda o *exporter* do
> ADOT — a aplicação continua instrumentada do mesmo jeito (sem lock-in).

---

## 🎯 Cenário de arquitetura (picos de tráfego)

> *"Temos uma aplicação crítica no EKS que sofre picos abruptos de tráfego. Como
> você desenharia essa arquitetura pensando em resiliência e custo na AWS?"*

Uma resposta arquitetural sólida combina **três camadas de escala/resiliência**:

1. **HPA (escala de Pods)** — baseado em métricas de **requisições por segundo**
   (via Prometheus/ALB), não só CPU/memória. RPS reflete melhor a carga real de
   uma API do que utilização de CPU.

2. **Karpenter (escala de nós)** — mistura de **instâncias Spot** (resiliência a
   baixo custo para *workloads* stateless) com **On-Demand como fallback**. Spot
   absorve o pico barato; On-Demand garante a base mesmo em interrupção de Spot.

3. **Topology Spread Constraints (distribuição)** — força as réplicas a se
   espalharem **uniformemente entre AZs**, evitando indisponibilidade se **uma AZ
   cair**.

### Os dois aprofundamentos possíveis

**A) Deploy multi-AZ com tratamento de falha de volume (EBS)**
O ponto sensível é o **EBS preso a uma AZ**. Se uma AZ cai, os Pods do
StatefulSet ancorados nela não conseguem reanexar o volume em outra AZ.
Estratégias: réplicas por AZ com volumes independentes (replicação no nível da
aplicação/DB), `topology.kubernetes.io/zone` no `StorageClass`
(`WaitForFirstConsumer`), ou migrar cargas RWX para **EFS** (multi-AZ nativo).

**B) Redução de custo com Spot + On-Demand no Karpenter**
Usar **NodePools** do Karpenter com prioridade a **Spot**, `On-Demand` como
fallback e **consolidação** de nós ociosos. Cargas stateless toleram interrupção
de Spot (com **PodDisruptionBudgets** e *graceful drain* nos ~2 min de aviso);
cargas críticas/stateful ficam em On-Demand. Ganho típico: **60–90%** no compute
stateless sem sacrificar disponibilidade.

---

## ✅ Checklist mental para a entrevista

- **Data Plane:** Managed vs. Self-Managed vs. Fargate · **Karpenter fala direto com EC2**, sem ASG.
- **Rede:** VPC CNI dá **IP real por Pod** → **IP Exhaustion** → *Custom Networking* / *Prefix Delegation*. ALB via Ingress + **target-type IP**.
- **Segurança:** **Pod Identities** (moderno) vs. **IRSA** (OIDC). **Security Groups for Pods** + Network Policies.
- **Storage:** **EBS = RWO, 1 AZ** (StatefulSet) · **EFS = RWX, multi-AZ**.
- **Observabilidade:** **Container Insights** (nativo) vs. **ADOT** (sem lock-in, → AMP/Grafana).
- **Cenário de pico:** **HPA (Pods) + Karpenter Spot/On-Demand (nós) + Topology Spread (AZs)**.
