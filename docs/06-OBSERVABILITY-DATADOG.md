# 06 — Monitoramento, Observabilidade e relação com Datadog

Pré-requisitos: `./lab.sh start k8s` e `./lab.sh start observability`. Gere tráfego: `./lab.sh traffic 300 5` (5 req/s por 5 min). Endereços: Grafana http://127.0.0.1:3000 (sem login) · Prometheus http://127.0.0.1:9090 · Loki :3100 · Tempo :3200.

## 1. Conceitos
- **Monitoramento:** vigiar sinais **conhecidos** e alertar (“a CPU passou de 80%?”). Responde *o que* está errado.
- **Observabilidade:** capacidade de entender o estado interno a partir das saídas (logs, métricas, traces) e responder perguntas **novas**, inclusive “por quê?”.
- **Os três pilares:**
  - **Métricas** — números agregados no tempo (barato, bom para alertar e tendências). Prometheus.
  - **Logs** — eventos detalhados (caro, bom para o contexto). Loki.
  - **Traces** — o caminho de **uma** requisição entre serviços, com tempo por etapa (*spans*). Tempo + OpenTelemetry.
- **APM (Application Performance Monitoring):** visão da aplicação: latência/erros por endpoint, traces, dependências, profiling. No lab = métricas HTTP do app + traces; no Datadog = produto *APM*.
- **OpenTelemetry (OTel):** padrão aberto (APIs/SDKs/protocolo OTLP) para gerar métricas/logs/traces sem prender-se a um fornecedor. O app do lab usa o SDK OTel (Flask) e exporta OTLP/HTTP para o Tempo (`OTEL_EXPORTER_OTLP_ENDPOINT=http://lab-tempo:4318`). Em produção costuma haver um *OTel Collector* no meio (omitido aqui para poupar RAM).

## 2. Os 4 Golden Signals (Google SRE)
| Sinal | Pergunta | Métrica no lab (PromQL) | Painel |
|---|---|---|---|
| **Latency** | quão rápido? | `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{path="/api/work"}[1m])))` | Latency p50/p95/p99 |
| **Traffic** | quanta demanda? | `sum by (path) (rate(http_requests_total[1m]))` | Traffic |
| **Errors** | quanto falha? | `sum(rate(http_requests_total{status=~"5.."}[1m])) / sum(rate(http_requests_total[1m]))` | Errors (%) |
| **Saturation** | quão cheio? | CPU: `rate(container_cpu_usage_seconds_total{container="app"}[1m])` e throttling `container_cpu_cfs_throttled_periods_total`; memória: `container_memory_working_set_bytes` vs `container_spec_memory_limit_bytes`; in-flight: `http_requests_in_flight` | Saturation |
Dica de entrevista: diferencie **latência de sucesso e de erro** (um 500 rápido “melhora” a média) e use **percentis**.
Método relacionado: **RED** (Rate, Errors, Duration — serviços) e **USE** (Utilization, Saturation, Errors — recursos).

## 3. Os componentes do lab
| Componente | Papel | Onde |
|---|---|---|
| App Flask | expõe `/metrics` (prometheus_client), logs JSON em stdout, traces OTel | ns `demo` |
| **Prometheus** | coleta (*scrape*) a cada 15 s: pods anotados `prometheus.io/scrape=true` e **cAdvisor** do kubelet (CPU/memória por container); avalia regras de alerta | ns `monitoring` ([k8s/addons/monitoring.yaml](../k8s/addons/monitoring.yaml)) |
| **Loki** | armazena logs indexando só labels (`namespace,pod,container,level`) | container `lab-loki` |
| **Alloy** | coletor: lê `/var/log/pods` (montado do node Kind) e envia ao Loki | container `lab-alloy` ([config.alloy](../observability/alloy/config.alloy)) |
| **Tempo** | armazena traces (OTLP) | container `lab-tempo` |
| **Grafana** | UI: datasources provisionados + dashboard *Golden Signals — lab-app* | :3000 |
Alertas: [regras no ConfigMap](../k8s/addons/monitoring.yaml) — `AppDown`, `HighErrorRate` (>5% 5xx), `HighLatencyP95` (>500 ms), `ContainerCpuThrottled` (>25%), `ContainerMemoryNearLimit` (>85% do limit). Estado em http://127.0.0.1:9090/alerts (sem Alertmanager: em produção ele roteia para Slack/PagerDuty/e-mail, agrupa e silencia).

## 4. Prática guiada
### 4.1 Dashboard e consultas
1. Grafana → *Dashboards* → pasta **DevOps Lab** → *Golden Signals — lab-app*. Com `./lab.sh traffic 120 5` rodando, veja as 4 seções (Latency/Traffic/Errors/Saturation) e os logs ao final.
2. Prometheus → *Graph* → cole as consultas da seção 2. Teste: `up`, `rate(http_requests_total[1m])`, `topk(3, sum by (path)(rate(http_requests_total[5m])))`.
3. Grafana → *Explore* → **Loki**: `{namespace="demo"}` · só erros: `{namespace="demo",level="ERROR"}` · filtrar: `{namespace="demo"} |= "api/work" | json | duration_ms > 100`. Contagem por minuto: `sum(count_over_time({namespace="demo"}[1m]))`.
4. Grafana → *Explore* → **Tempo** → *Search* → Service Name `lab-app` → abra um trace e veja o span `GET /api/work` com duração. (Chame o app algumas vezes antes: `curl -s localhost:30080/api/work`.)

### 4.2 Incidentes observáveis
| Exercício | O que ver no Grafana/Prometheus |
|---|---|
| `./lab.sh exercise http-500` | painel *Errors*: 5xx ≈ 40%; alerta `HighErrorRate`; logs `level=ERROR` |
| `./lab.sh exercise high-latency` | *Latency* p95 ≈ 2,4 s (medido), alerta `HighLatencyP95`; CPU baixa (não é saturação); logs com `duration_ms` > 1000 |
| `./lab.sh exercise high-cpu` | *Saturation*: CPU = limit (0,2) e throttling alto; `ContainerCpuThrottled`; `kubectl top pod` |
| `./lab.sh exercise oomkilled` | memória sobe até o limit e o container reinicia; `ContainerMemoryNearLimit` |
| disponibilidade | `kubectl -n demo scale deploy/lab-app --replicas=0` → `AppDown` fica *pending* (~1 min) e depois *firing* (~2 min; observado: pending aos 100 s); volte com `--replicas=2` |
Os alertas levam 1–2 min (`for: 1m` + intervalo de scrape). Os valores citados vieram de execuções reais neste lab.

### 4.3 Ler um alerta
Exemplo `HighErrorRate`: `expr` (condição), `for` (tempo contínuo antes de disparar — evita ruído), `labels.severity`, `annotations.summary`. Estados: *inactive → pending → firing*. Bons alertas são **acionáveis** e baseados em sintomas (erros, latência), não em causas (CPU 80%); use **SLO** e *burn rate* para alertar sobre orçamento de erro.

## 5. Relação com o Datadog (sem usar o Datadog)
O Datadog é uma plataforma SaaS que junta tudo isso. Os conceitos são os mesmos; muda o empacotamento.
| Conceito | Lab local | Datadog |
|---|---|---|
| Coleta | Prometheus scrape, Alloy, OTel SDK | **Datadog Agent** (DaemonSet no K8s; Cluster Agent) + integrações; também aceita OTLP |
| Métricas | Prometheus + PromQL | **Metrics** (métricas `kubernetes.*`, `container.*`, custom via DogStatsD); consulta própria; Metrics Explorer |
| Logs | Loki + LogQL | **Log Management** (pipelines, índices, Live Tail, Logs → Metrics) |
| Traces / APM | Tempo + OTel | **APM** (Service Map, Service Catalog, flame graph, Continuous Profiler), **distributed tracing** com `dd-trace` ou OTel |
| Dashboards | Grafana | **Dashboards** / Notebooks / Screenboards |
| Alertas | regras Prometheus (+Alertmanager) | **Monitors** (metric, log, APM, anomaly, composite, SLO) com notificações Slack/PagerDuty |
| Disponibilidade externa | `curl`/probes | **Synthetic Monitoring** (testes de API/browser) |
| Usuário real | — | **RUM** (Real User Monitoring) |
| SLOs | PromQL manual | **SLOs** nativos + error budget |
| Kubernetes | `kubectl`, cAdvisor, kube-state-metrics | **Orchestrator Explorer**, Live Containers, Kubernetes Overview |
| Infra/rede | node-exporter | Infrastructure List, NPM (rede), Cloud integrations (AWS/Azure) |
| Segurança | Trivy | Cloud Security, Code Security (SAST/SCA) |
| Correlação | trace ↔ logs via datasource | **unified service tagging** (`env`, `service`, `version`) liga métricas, logs e traces automaticamente |
| Custo | RAM/disco seus | por host, por GB de log, por span/custom metric (**cuidado com cardinalidade** de tags) |
Como seria o mesmo incidente no Datadog (ex.: `http-500`): *Monitor* de taxa de erro dispara → página do serviço em **APM** mostra erros por endpoint → clique no *trace* com erro → botão para **logs correlacionados** do mesmo `trace_id` → *Deployment Tracking* mostra a `version` onde o erro começou → abre-se um *Incident* (Datadog Incident Management) para o RCA.
Equivalências de consulta: PromQL `sum(rate(http_requests_total{status=~"5.."}[1m]))` ≈ Datadog `sum:trace.flask.request.errors{service:lab-app}.as_rate()`.

## 6. Perguntas de entrevista
1. Monitoramento × observabilidade? 2. Por que percentis? 3. O que são labels/cardinalidade e por que alta cardinalidade é problema (memória no Prometheus, custo no Datadog)?
4. Pull (Prometheus) × push (Datadog Agent/StatsD)? 5. Como reduzir ruído de alertas (for, agrupamento, SLO/burn rate, severidade)?
6. Como correlacionar log e trace? (propagar `trace_id` no log.) 7. O que mede CPU throttling e por que `top` do node não mostra?
