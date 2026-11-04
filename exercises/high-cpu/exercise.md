# Aplicação com CPU elevada (throttling)

## Objetivo
Identificar consumo de CPU por pod, entender limit/throttling e correlacionar com latência.

## Contexto do incidente
Um pod `burner` está lento. O time de monitoramento notou CPU "colada" em 200m.

## Como reproduzir
```bash
./lab.sh exercise high-cpu
```
Pod com `limits.cpu: 200m`; o script chama `/cpu?seconds=900` (um loop que consome 1 core por 15 min).

## Investigação
```bash
NS=inc-high-cpu
kubectl -n $NS top pod                         # após ~60s: CPU(cores) ≈ 200m (exatamente o limit)
kubectl -n $NS logs deploy/burner | tail -3    # "consumo de CPU iniciado"
kubectl -n $NS exec deploy/burner -- cat /sys/fs/cgroup/cpu.stat    # nr_throttled / throttled_usec crescendo
kubectl -n $NS exec deploy/burner -- python -c "print(open('/proc/loadavg').read())"
```
No Prometheus: `rate(container_cpu_usage_seconds_total{namespace="inc-high-cpu",container="app"}[1m])` (≈0.2) e a razão de `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` (alta). Alerta `ContainerCpuThrottled` dispara em ~1–2 min.

**Como interpretar:** uso encostado no limit + `nr_throttled` crescendo = o container *queria* mais CPU e o kernel o freou. Latência das requisições normais sobe (veja `/api/hello` demorando).

## Causa-raiz
Uma requisição (`/cpu`) inicia trabalho CPU-bound sem controle no mesmo processo que atende tráfego.

## Como resolver
```bash
./lab.sh exercise high-cpu fix     # rollout restart: mitigação imediata
```
Correção real: isolar trabalho pesado (fila/worker), limitar concorrência, otimizar. Subir o limit só adia o problema; HPA ajuda com carga legítima, não com loop descontrolado.

## Como validar
`./lab.sh exercise high-cpu validate` → `kubectl top pod` volta para poucos millicores.

## Limpeza
`./lab.sh exercise high-cpu reset`

## Modelo de RCA (resumo)
Causa: processamento CPU-bound sem proteção. Detecção: alerta de throttling. Prevenção: rate limit, limites de timeout, perf test, HPA.

## Perguntas de revisão
1. O que significa throttling? (CFS quota: o container só roda `limit` ms a cada 100 ms.)
2. `top` do node mostra CPU baixa mas o pod está lento. Por quê? (throttling por limit.)
3. Request vs limit de CPU: efeito no scheduling e na execução?
4. Quando usar HPA e em que métrica?
