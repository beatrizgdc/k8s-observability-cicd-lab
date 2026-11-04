# Aplicação com latência elevada

## Objetivo
Medir latência (p50/p95/p99), localizar onde está o tempo gasto e correlacionar métrica, log e trace.

## Contexto do incidente
Usuários reclamam de lentidão em `/api/work`. Sem erros, sem restart: "está só devagar".

## Como reproduzir
```bash
./lab.sh start observability
./lab.sh exercise high-latency
```
`FAULT_LATENCY_MS=1500` via ConfigMap em `inc-high-latency`, com tráfego contínuo.

## Investigação
```bash
NS=inc-high-latency
kubectl -n $NS exec deploy/load -- sh -c 'time wget -q -O /dev/null http://api/api/work'     # ~1.5 s
kubectl -n $NS logs -l app=api --tail=5 | grep duration_ms                                    # duration_ms ≈ 1500
kubectl -n $NS top pod                                                                       # CPU baixa => não é saturação
kubectl -n $NS get configmap api-config -o yaml
```
Prometheus: `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="inc-high-latency",path="/api/work"}[1m])))` (medido neste lab: ≈2,4 s). Alerta `HighLatencyP95`.
Loki: `{namespace="inc-high-latency",container="app"} | json | duration_ms > 1000`.
Tempo (Grafana → Explore → Tempo → Search, service `lab-app`): cada trace mostra um span longo no handler `/api/work`.

**Como interpretar:** latência alta + CPU baixa + sem erros ⇒ a app **espera** algo (dependência lenta, lock, sleep). Se CPU estivesse no limit seria throttling (exercício high-cpu).

## Causa-raiz
Latência artificial injetada por configuração (`FAULT_LATENCY_MS`), simulando uma dependência lenta.

## Como resolver
```bash
./lab.sh exercise high-latency fix     # ConfigMap = 0 + rollout restart
```

## Como validar
`./lab.sh exercise high-latency validate`; no Grafana o p95 volta a ~50 ms.

## Limpeza
`./lab.sh exercise high-latency reset`

## Modelo de RCA (resumo)
Causa: dependência/config lenta. Detecção: alerta p95. Prevenção: timeouts + circuit breaker, SLO de latência, tracing.

## Perguntas de revisão
1. Por que usar percentis e não média? (média esconde cauda.)
2. Latência alta: como saber se é CPU, I/O, rede ou dependência?
3. O que é um trace/span e quando é melhor que logs?
4. Qual a diferença entre latência e throughput (traffic)?
