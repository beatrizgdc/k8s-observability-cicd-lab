# Container morto por OOMKilled

## Objetivo
Distinguir "app com bug" de "limit de memória baixo" e ler `OOMKilled`/exit code 137.

## Contexto do incidente
O serviço `leaky` reinicia sozinho após receber certas requisições; clientes veem conexões cortadas.

## Como reproduzir
```bash
./lab.sh exercise oomkilled
```
Deployment com `limits.memory: 100Mi`; o script chama `/memory?mb=150`, que aloca 150 MB e os mantém.

## Investigação
```bash
NS=inc-oomkilled
kubectl -n $NS get pods                                              # RESTARTS = 1
kubectl -n $NS describe pod -l app=leaky | grep -A8 "Last State"     # Reason: OOMKilled, Exit Code: 137
kubectl -n $NS top pod                                               # uso atual vs limit
kubectl -n $NS get pod -l app=leaky -o jsonpath='{.items[0].spec.containers[0].resources}'
```
No Grafana (dashboard Golden Signals → Saturation) a memória sobe até a linha do limit e cai (restart). No Prometheus:
`container_memory_working_set_bytes{namespace="inc-oomkilled",container="app"}`.

**Como interpretar:** `OOMKilled` = o kernel (cgroup) matou o processo por ultrapassar o limit. Exit 137 = 128 + 9 (SIGKILL). Diferente de *evicted* (node sem memória).

## Causa-raiz
A requisição consome mais memória (150 MB + base ≈ 60 MB) que o limit (100 Mi). Pode ser limit subdimensionado **ou** vazamento/pico no código; é preciso medir antes de aumentar.

## Como resolver
```bash
./lab.sh exercise oomkilled fix
# equivalente a: kubectl -n inc-oomkilled set resources deploy/leaky --limits=memory=300Mi --requests=memory=128Mi
```
Aumentar o limit é **mitigação**. A correção real é achar por que o app precisa de tanta memória (profiling, paginação, cache sem limite).

## Como validar
```bash
./lab.sh exercise oomkilled validate     # chama /memory?mb=150 novamente: sem OOM; RESTARTS do pod novo = 0
```

## Limpeza
`./lab.sh exercise oomkilled reset`

## Modelo de RCA (resumo)
Causa: pico de memória > limit. Detecção: alerta `ContainerMemoryNearLimit` (>85% do limit) deveria ter avisado antes. Prevenção: alerta de saturação, teste de carga, requests = uso típico, limit = pico + margem.

## Perguntas de revisão
1. Qual a diferença entre request e limit de memória? (request = reserva p/ scheduling; limit = teto, estourou → OOMKilled.)
2. Por que CPU acima do limit é "throttled" e memória é "killed"? (CPU é compressível; memória não.)
3. O que é a QoS class (Guaranteed/Burstable/BestEffort) e como influencia evictions?
4. Como diferenciar OOMKilled de Evicted? (`describe`: Reason; Evicted aparece no status do Pod com mensagem do node pressure.)
