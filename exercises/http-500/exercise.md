# Aplicação retornando HTTP 500

## Objetivo
Investigar aumento de erros 5xx usando logs, métricas (RED/Golden Signals) e alerta; entender que ConfigMap só vale após restart.

## Contexto do incidente
Depois de uma mudança de configuração, ~40% das chamadas a `/api/work` falham com HTTP 500. Pods continuam Ready (o health check não pega o problema).

## Como reproduzir
```bash
./lab.sh start observability      # recomendado (Grafana/Loki); o incidente roda mesmo sem
./lab.sh exercise http-500
```
Cria `inc-http-500` com `api` (2 réplicas, `FAULT_ERROR_RATE=0.4` vindo de um ConfigMap) e `load` (gerador de tráfego).

## Investigação
```bash
NS=inc-http-500
kubectl -n $NS get pods                                       # tudo Running/Ready: o problema é lógico
kubectl -n $NS logs -l app=api --tail=50 --prefix | grep ERROR
kubectl -n $NS logs -l app=api --tail=500 | grep -c '"status": 500'
kubectl -n $NS get configmap api-config -o yaml               # FAULT_ERROR_RATE: "0.4"
kubectl -n $NS exec deploy/api -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8080/info').read().decode())"   # "faults" mostra a config ativa
```
Prometheus (http://127.0.0.1:9090): `sum(rate(http_requests_total{namespace="inc-http-500",status="500"}[1m])) / sum(rate(http_requests_total{namespace="inc-http-500"}[1m]))` (≈0.4). Alerta `HighErrorRate` em `/alerts`.
Grafana (http://127.0.0.1:3000 → Golden Signals): painel *Errors*. Loki: `{namespace="inc-http-500"} |= "ERROR"`.

**Como interpretar:** mesmo erro nos 2 pods ⇒ causa comum (config/deploy), não um pod ruim. Logs dizem `erro interno simulado` com `error="backend indisponivel"`.

## Causa-raiz
Valor incorreto (`FAULT_ERROR_RATE=0.4`) publicado na configuração; a app o lê no start.

## Como resolver
```bash
./lab.sh exercise http-500 fix
# kubectl -n inc-http-500 patch configmap api-config --type merge -p '{"data":{"FAULT_ERROR_RATE":"0"}}'
# kubectl -n inc-http-500 rollout restart deploy/api     # SEM isto, os pods antigos mantêm o valor!
```

## Como validar
`./lab.sh exercise http-500 validate` → 5 respostas 200. Em ~2 min a taxa de 5xx cai a 0 no Grafana e o alerta resolve.

## Limpeza
`./lab.sh exercise http-500 reset`

## Modelo de RCA (resumo)
Causa: configuração inválida em produção. Detecção: alerta HighErrorRate. Correção: rollback da config + restart. Prevenção: canary/rollout gradual, validação de config, SLO com burn-rate.

## Perguntas de revisão
1. Como diferenciar erro de aplicação (5xx) de erro do cliente (4xx)?
2. Readiness OK e 500 alto: por que o K8s não resolve sozinho? (probe não cobre a lógica.)
3. Por que mudar o ConfigMap não alterou o comportamento? (env vars só na criação do container; volume monta atualiza, env não.)
4. O que é SLI/SLO/error budget? Qual SLI você usaria aqui?
