# 🔭 Observabilidade em EKS — Prometheus & Dynatrace (Prep. de Entrevista)

![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)
![Dynatrace](https://img.shields.io/badge/Dynatrace-1496FF?style=for-the-badge&logo=dynatrace&logoColor=white)

Guia de estudo, no formato **pergunta → resposta de peso**, sobre como desenhar
observabilidade num cluster **Amazon EKS** usando **Prometheus** (open source /
cloud-native) e **Dynatrace** (APM comercial full-stack). Complementa o
[README principal](../README.md) do lab de arquitetura.

> **Como usar:** cada seção abre com o conceito, mostra como cai em entrevista e
> fecha com a resposta que demonstra senioridade. As decisões arquiteturais estão
> sempre amarradas às **particularidades do EKS** (VPC CNI, IRSA/Pod Identity, ALB).

---

## 0. O modelo mental: os 3 (ou 4) pilares

Antes de citar ferramentas, mostre que você entende **o quê** está observando.

| Pilar | Pergunta que responde | Prometheus | Dynatrace |
|---|---|---|---|
| **Métricas** | "Está saudável? Quanto consome?" | Nativo (TSDB + PromQL) | Nativo (Grail + DQL) |
| **Logs** | "O que aconteceu exatamente?" | Não é forte (Loki no ecossistema) | Nativo (Log Monitoring) |
| **Traces** | "Onde o request gastou tempo?" | Via OpenTelemetry/Tempo | Nativo (PurePath / distributed tracing) |
| **Eventos/Topologia** | "O que mudou? Como se conecta?" | K8s events (parcial) | Smartscape (topologia automática) |

> **Frase de peso:** *"Métricas dizem que algo está errado; traces dizem onde; logs
> dizem o porquê. Observabilidade é conseguir responder perguntas que você não
> sabia que teria — diferente de monitoramento, que só checa dashboards pré-definidos."*

**MELT** = **M**etrics, **E**vents, **L**ogs, **T**races — o vocabulário moderno.

---

## 1. Os 3 níveis de observabilidade num cluster EKS

Um candidato sênior separa **o que** monitorar em três camadas — a pergunta clássica
é *"como você observa um cluster ponta a ponta?"*.

```
┌──────────────────────────────────────────────────────────┐
│ 3. APLICAÇÃO      → latência, erros, throughput (RED),     │
│                     traces distribuídos, métricas de negócio│
├──────────────────────────────────────────────────────────┤
│ 2. KUBERNETES     → estado de Pods/Deployments, kube-state, │
│                     scheduling, HPA, restarts, OOMKilled    │
├──────────────────────────────────────────────────────────┤
│ 1. INFRAESTRUTURA → nós EC2, CPU/mem/disk (node-exporter),  │
│                     rede VPC CNI, control plane do EKS       │
└──────────────────────────────────────────────────────────┘
```

- **Control Plane do EKS é gerenciado pela AWS** — você **não** roda Prometheus nos
  masters. As métricas do control plane vêm do endpoint `/metrics` do `kube-apiserver`
  (exposto via API) e dos **EKS Control Plane logs** no CloudWatch (api, audit,
  authenticator, controllerManager, scheduler).
- **Data plane (worker nodes) é seu** — é aqui que os agentes (node-exporter,
  OneAgent) e coletores rodam, tipicamente como **DaemonSet**.

> **Método RED** (serviços): **R**ate, **E**rrors, **D**uration.
> **Método USE** (recursos): **U**tilization, **S**aturation, **E**rrors.
> **4 Golden Signals** (Google SRE): latência, tráfego, erros, saturação.

---

## 2. Stack Prometheus no EKS

### 2.1 Componentes (o que cai em entrevista)

| Componente | Função |
|---|---|
| **Prometheus Server** | Faz **scrape** (pull) dos `/metrics`, guarda na TSDB, avalia rules |
| **node-exporter** | DaemonSet — métricas de SO/hardware de cada nó (USE) |
| **kube-state-metrics (KSM)** | Estado dos objetos K8s (Deployments, Pods, réplicas desejadas vs. prontas) |
| **Alertmanager** | Deduplica, agrupa e **roteia** alertas (Slack, PagerDuty, e-mail) |
| **Grafana** | Visualização (dashboards, PromQL) |
| **Prometheus Operator** | CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`) — instala via `kube-prometheus-stack` |

> **Pegadinha comum:** *"node-exporter e kube-state-metrics medem a mesma coisa?"*
> **Não.** node-exporter = **recursos do host** (CPU, disco, rede do nó).
> KSM = **estado da API do K8s** (quantos Pods `Running`, réplicas indisponíveis).
> São complementares.

### 2.2 Pull vs. Push (a pergunta favorita)

> **P: Por que o Prometheus usa modelo *pull* (scrape) em vez de *push*?**
>
> **R:** O servidor Prometheus **descobre** os targets (via service discovery do K8s)
> e **puxa** as métricas periodicamente. Vantagens: (1) o Prometheus sabe se um
> target está *down* (scrape falhou = target caiu — é um health check de graça);
> (2) sem necessidade de os apps conhecerem o endereço do backend; (3) controle
> centralizado de frequência. Para jobs efêmeros (batch/CronJob) que morrem antes
> do scrape, usa-se o **Pushgateway** — a exceção que confirma a regra.

### 2.3 Service Discovery no EKS

O Prometheus descobre targets pela **API do Kubernetes** (`kubernetes_sd_config`):
Pods, Services, Endpoints, Nodes. Com o **Operator**, você declara um
**`ServiceMonitor`** que casa por *labels* — não edita `prometheus.yml` na mão.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-app
  namespace: time-a
spec:
  selector:
    matchLabels:
      app: demo          # casa com o Service que tem esse label
  endpoints:
    - port: metrics      # nome da porta no Service
      interval: 30s
      path: /metrics
```

### 2.4 PromQL — o mínimo para não travar

```promql
# Taxa de erros HTTP 5xx (método RED — Errors)
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)

# Uso de CPU por Pod (cores)
sum(rate(container_cpu_usage_seconds_total{namespace="time-a"}[5m])) by (pod)

# Pods reiniciando (crash loop)
increase(kube_pod_container_status_restarts_total[15m]) > 3

# Memória vs. limit (risco de OOMKilled)
container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.9
```

> `rate()` = média por segundo de um **counter** numa janela; `increase()` = total
> na janela; use `histogram_quantile()` para percentis (p95/p99) de latência a
> partir de um **histogram**. Erro clássico de júnior: usar `avg` de latência em vez
> de **p99** — a média esconde a cauda que mata a experiência do usuário.

---

## 3. Prometheus **gerenciado** na AWS (AMP + AMG)

Rodar Prometheus self-managed dá trabalho: **HA, retenção, escala da TSDB**. Saber
as opções gerenciadas mostra maturidade de custo/operação.

| Opção | O que é |
|---|---|
| **Amazon Managed Service for Prometheus (AMP)** | TSDB gerenciada, compatível com PromQL, **retenção e HA sem operar servidor**. Você só faz o `remote_write` para lá. |
| **Amazon Managed Grafana (AMG)** | Grafana gerenciado, com login via IAM Identity Center/SSO. |
| **ADOT (AWS Distro for OpenTelemetry)** | Coletor padrão de mercado para **scrapear** e fazer `remote_write` ao AMP — sem vendor lock-in. |
| **CloudWatch Container Insights** | Métricas/logs de infra "plug-and-play", com a opção *Prometheus metrics* e agora o **Enhanced Observability**. |

> **Padrão de referência atual:** agente coletor (**ADOT** ou o próprio Prometheus
> agent-mode) roda como DaemonSet no EKS, faz o scrape local e usa **`remote_write`**
> para o **AMP**; visualização no **AMG**. Você opera só o coletor — a TSDB pesada é
> serverless. Autenticação do `remote_write` via **IRSA/EKS Pod Identity** (sem chave
> estática), assinado com **SigV4**.

> 🛠️ **Quer ver esse padrão em Terraform?** O guia
> [Stack de Observabilidade (ADOT → AMP → Grafana)](OBSERVABILIDADE-STACK-ADOT-AMP.md)
> mostra, no padrão deste lab, como montar módulo + stack com IRSA de privilégio mínimo.

```
Pods (/metrics) ─► ADOT Collector (DaemonSet) ─► remote_write (SigV4/IRSA) ─► AMP ─► AMG
```

---

## 4. Dynatrace no EKS

Dynatrace é **APM full-stack comercial**: a proposta é *"instale um agente e ele
descobre tudo sozinho"* — métricas, logs, traces e topologia, com IA de causa-raiz.

### 4.1 Como ele coleta — o OneAgent

| Elemento | Função |
|---|---|
| **OneAgent** | Roda como **DaemonSet** (1 por nó). Instrumenta o host **e** injeta instrumentação nos processos das apps automaticamente (auto-injection) — Java, .NET, Node, Go, etc. |
| **Dynatrace Operator** | CRD que gerencia o ciclo de vida do OneAgent e do ActiveGate no cluster. |
| **ActiveGate** | Proxy/gateway que agrega e encaminha dados para o tenant Dynatrace (SaaS/Managed); também coleta métricas via a **Kubernetes API** e **Prometheus scrape**. |
| **Grail + DQL** | Data lakehouse do Dynatrace e sua linguagem de query (equivalente conceitual ao PromQL/SQL). |
| **Davis AI** | Motor de detecção de anomalias e **análise de causa-raiz** automática. |

> **PurePath** = o trace distribuído do Dynatrace, ponta a ponta, com código, SQL e
> latência por hop. **Smartscape** = mapa de **topologia automático** (quem fala com
> quem), atualizado em tempo real — não precisa desenhar arquitetura na mão.

### 4.2 Modos de deploy no Kubernetes (pergunta de arquiteto)

O Dynatrace Operator suporta modos que **trocam cobertura por overhead**:

| Modo | Como funciona | Trade-off |
|---|---|---|
| **classicFullStack** | OneAgent no host + injeção em todos os processos | Cobertura total; maior footprint |
| **cloudNativeFullStack** | OneAgent como DaemonSet + `applicationMonitoring` via webhook de injeção | **Recomendado em K8s** — full-stack com deploy cloud-native |
| **applicationMonitoring** (só app) | Só injeta nas apps (sem métricas de host aprofundadas) | Leve; menos visibilidade de infra |
| **hostMonitoring** | Só o host (sem injeção nas apps) | Infra apenas |

> **Frase de peso:** *"Em EKS eu uso `cloudNativeFullStack`: o OneAgent sobe como
> DaemonSet e a injeção nas aplicações acontece por um webhook de admission, então
> não preciso reconstruir imagem nem alterar manifesto da app para ganhar tracing."*

### 4.3 Kubernetes-native no Dynatrace

- **Kubernetes monitoring**: descobre o cluster via a **API**, mostra workloads,
  eventos, capacidade e saúde do control plane do EKS.
- **Prometheus ingest**: o Dynatrace **consome métricas Prometheus** (annotation
  `metrics.dynatrace.com/scrape: "true"` ou via ActiveGate) — ou seja, **não é um
  ou outro**: dá para levar suas métricas `/metrics` existentes para dentro do
  Dynatrace.
- **Log Monitoring**: coleta logs de container direto do nó, correlacionando com o
  trace/entidade que os gerou.

---

## 5. Prometheus **vs.** Dynatrace — quando usar cada um

A pergunta que separa o júnior do sênior: *"por que escolher um em vez do outro?"* —
e a resposta madura é quase sempre **"depende, e frequentemente os dois convivem"**.

| Critério | Prometheus (+ Grafana/AMP) | Dynatrace |
|---|---|---|
| **Modelo** | Open source / gerenciado (AMP) | Comercial (licença por host/GiB) |
| **Custo** | Infra + operação (ou AMP por ingestão) | Licença por consumo — pode escalar caro |
| **Coleta** | **Pull** (scrape) — você instrumenta | **Auto-injection** (OneAgent) — quase zero config |
| **Traces** | Precisa OpenTelemetry + Tempo/Jaeger | PurePath nativo, ponta a ponta |
| **Topologia** | Manual (dashboards) | Smartscape automático |
| **Causa-raiz** | Você investiga (PromQL + dashboards) | Davis AI aponta automaticamente |
| **Vendor lock-in** | Baixo (PromQL/OTel são padrões) | Alto |
| **Curva** | Você monta tudo (flexível) | Rápido para valor, menos flexível |
| **Ideal para** | Métricas de infra/K8s, custo controlado, equipe cloud-native | APM full-stack, times que querem valor rápido e RCA por IA |

> **Resposta de arquiteto (o "e" em vez do "ou"):**
> *"Numa organização real eu combino: **Prometheus/AMP** como espinha dorsal de
> métricas de infraestrutura e Kubernetes (barato, padrão de mercado, sem lock-in),
> e **Dynatrace** onde o valor de APM full-stack justifica a licença — aplicações
> críticas de negócio que precisam de tracing profundo e causa-raiz por IA. O
> **OpenTelemetry** é a cola: instrumento as apps uma vez em OTel e decido para onde
> exportar, evitando reinstrumentar se trocar de backend."*

---

## 6. O papel do **OpenTelemetry** (OTel)

Cai muito porque é a **estratégia anti-lock-in** que ambos os mundos aceitam.

- **OTel = padrão aberto** de instrumentação (APIs, SDKs e o **Collector**) para
  métricas, logs e **traces**.
- Você instrumenta a app **uma vez** e o **Collector** exporta para o destino:
  Prometheus/AMP, Tempo, **ou Dynatrace** (que ingere OTLP nativamente).
- No EKS, a AWS entrega isso como **ADOT** (AWS Distro for OpenTelemetry) —
  suportado e com integrações prontas para AMP, X-Ray e CloudWatch.

```
App (SDK OTel) ─► OTel/ADOT Collector ─┬─► AMP (métricas)
                                        ├─► Tempo/Jaeger/X-Ray (traces)
                                        └─► Dynatrace (OTLP) — se preferir consolidar
```

> **Frase de peso:** *"OpenTelemetry desacopla instrumentação de backend. Isso
> transforma a escolha Prometheus vs. Dynatrace numa decisão de **exportador**, não
> de reescrita de código."*

---

## 7. Especificidades do EKS que caem na parte de observabilidade

Aqui é onde você amarra observabilidade às particularidades da AWS (o diferencial).

- **Autenticação sem chave estática:** o coletor (ADOT/Prometheus) que faz
  `remote_write` para o **AMP** assume uma **Role IAM via IRSA ou EKS Pod Identity**
  — coerente com o princípio de **privilégio mínimo** (nada de `AWS_ACCESS_KEY_ID`
  no Pod). Ver o pilar de IRSA no [README principal](../README.md#1️⃣-segurança-e-identidade--irsa).
- **VPC CNI e IP real por Pod:** métricas de rede a nível de Pod fazem sentido porque
  cada Pod tem **IP roteável da VPC**. Fique atento à métrica de **IP exhaustion**
  (subnets `/24` esgotam) — monitorar IPs livres da subnet é um alerta de produção.
- **Control plane logs:** habilitar os **EKS control plane logs** (audit,
  authenticator...) no CloudWatch é parte da observabilidade — o `kube-apiserver`
  não é seu, mas os logs dele são.
- **DaemonSet é o padrão de coleta:** node-exporter, OneAgent e coletores rodam como
  **DaemonSet** (1 por nó). ⚠️ **Fargate não suporta DaemonSet** — em nós Fargate
  a coleta muda (sidecar/ADOT como sidecar, ou Dynatrace `applicationMonitoring`).
- **Karpenter e nós efêmeros:** com nós subindo/descendo em segundos, a
  observabilidade precisa lidar com **alta rotatividade de targets** — service
  discovery dinâmico (o *pull* do Prometheus se reconfigura sozinho) é uma vantagem.
- **Custo de observabilidade:** ingestão de métricas/logs custa dinheiro (AMP por
  amostra, CloudWatch por GiB, Dynatrace por host/GiB). Cardinality alta (labels
  explodindo) é o vilão nº 1 de custo em Prometheus — **controlar labels** é
  discussão de sênior.

> **Cardinalidade (pergunta-armadilha):** cada combinação única de labels vira uma
> *time series*. Colocar `user_id` ou `request_id` como label **explode a TSDB** e o
> custo. Regra: labels são para **dimensões de baixa cardinalidade** (status, método,
> rota *normalizada*), nunca identificadores únicos.

---

## 8. Cenário de arquitetura (como responder o "desenhe para mim")

> *"Aplicação crítica no EKS com picos de tráfego. Desenhe a observabilidade
> pensando em resiliência, causa-raiz rápida e custo."*

**Resposta estruturada:**

1. **Instrumentação padrão:** apps em **OpenTelemetry** (traces + métricas custom de
   negócio, ex.: requests/s por endpoint).
2. **Métricas de infra/K8s:** **ADOT DaemonSet** faz scrape (node-exporter +
   kube-state-metrics) e `remote_write` para **AMP** — autenticado por **IRSA**.
   Visualização no **Amazon Managed Grafana**.
3. **APM/RCA nas apps críticas:** **Dynatrace** `cloudNativeFullStack` para PurePath
   + Davis AI, restrito aos namespaces de negócio para conter licença.
4. **Alertas:** `PrometheusRule`/Alertmanager (ou Davis) nos **4 Golden Signals** —
   latência p99, erro 5xx, saturação de CPU/mem, tráfego. Roteia para PagerDuty.
5. **Correlação com escala:** métrica de **requests/s** alimenta o **HPA**; o
   **Karpenter** provisiona Spot+On-Demand. A observabilidade fecha o loop: você vê
   o pico → HPA escala Pods → Karpenter escala nós → dashboards confirmam.
6. **Controle de custo:** retenção curta no AMP, sampling de traces (ex.: 10% + 100%
   dos erros), labels de baixa cardinalidade, Dynatrace só onde paga a licença.
7. **Resiliência do próprio monitoramento:** coletor em DaemonSet (não morre com 1
   Pod), backend gerenciado (AMP/Dynatrace SaaS) para não ter "quem monitora o
   monitor" caindo junto com o cluster.

> **Fechamento:** *"Observabilidade não é dashboard bonito — é MTTR baixo. O desenho
> otimiza para responder **'o que quebrou e por quê'** em minutos, sem estourar a
> conta com cardinalidade e licença desnecessária."*

---

## 9. Perguntas rápidas (flashcards)

| Pergunta | Resposta curta |
|---|---|
| Prometheus é pull ou push? | **Pull** (scrape); Pushgateway só para jobs efêmeros. |
| node-exporter vs. kube-state-metrics? | Host (recursos) vs. estado da API do K8s. |
| Como Prometheus acha os Pods no EKS? | Service discovery via **API do K8s** (`ServiceMonitor`). |
| O que é AMP? | **Amazon Managed Service for Prometheus** — TSDB serverless, PromQL. |
| Como o coletor autentica no AMP? | **IRSA / EKS Pod Identity** + SigV4 (sem chave estática). |
| O que é o OneAgent? | Agente Dynatrace (DaemonSet) com **auto-injection** nas apps. |
| Modo Dynatrace recomendado em K8s? | **cloudNativeFullStack**. |
| PurePath vs. Smartscape? | Trace distribuído vs. mapa de topologia automático. |
| Papel do OpenTelemetry? | Instrumentação **padrão e portável** — anti-lock-in. |
| ADOT é o quê? | AWS Distro for OpenTelemetry — coletor OTel suportado pela AWS. |
| Por que p99 e não média de latência? | A média esconde a **cauda** que degrada a UX. |
| Vilão de custo no Prometheus? | **Alta cardinalidade** (labels com IDs únicos). |
| Fargate suporta DaemonSet? | **Não** — muda a estratégia de coleta (sidecar). |
| Onde ficam os logs do control plane do EKS? | **CloudWatch** (EKS control plane logs). |
| 4 Golden Signals? | Latência, tráfego, erros, saturação. |

---

## 📚 Referências

- Amazon Managed Service for Prometheus — https://docs.aws.amazon.com/prometheus/
- Amazon Managed Grafana — https://docs.aws.amazon.com/grafana/
- AWS Distro for OpenTelemetry (ADOT) — https://aws-otel.github.io/
- Prometheus Operator / kube-prometheus-stack — https://prometheus-operator.dev/
- Dynatrace on Kubernetes / Operator — https://docs.dynatrace.com/docs/setup-and-configuration/setup-on-k8s
- OpenTelemetry — https://opentelemetry.io/docs/
- EKS Best Practices — Observability — https://docs.aws.amazon.com/eks/latest/best-practices/
