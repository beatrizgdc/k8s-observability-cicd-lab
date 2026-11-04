# Deploy com versão incorreta — rollout travado e rollback

## Objetivo
Praticar `rollout status/history/undo` e entender como `maxUnavailable: 0` + readiness protegem o serviço.

## Contexto do incidente
Release 2.0.0 do `shop` foi aplicada. Alguns minutos depois, o pipeline de deploy "pendura" em *Waiting for rollout to finish*.

## Como reproduzir
```bash
./lab.sh exercise rollback
```
Aplica v1.0.0 (3 réplicas, estável) e depois v2.0.0 com `FAIL_HEALTH=1` (health checks respondem 503).

## Investigação
```bash
NS=inc-rollback
kubectl -n $NS rollout status deploy/shop --timeout=20s    # "Waiting for ... 1 out of 3 new replicas..." e timeout
kubectl -n $NS get pods                                    # 3 antigos 1/1; 1 novo 0/1 (readiness falha)
kubectl -n $NS get rs                                      # 2 ReplicaSets: o novo com 1 pod, o antigo com 3
kubectl -n $NS describe pod -l app=shop | grep -E "Readiness|Unhealthy"   # "Readiness probe failed: HTTP probe failed with statuscode: 503"
kubectl -n $NS rollout history deploy/shop                 # revisões e change-cause
kubectl -n $NS get events --sort-by=.lastTimestamp | tail
```
**Como interpretar:** com `maxUnavailable: 0` o Kubernetes **não remove** pods antigos enquanto os novos não ficam Ready ⇒ usuários seguem na v1; o deploy fica pendente (`progressDeadlineSeconds` 600s depois marca `ProgressDeadlineExceeded`).

## Causa-raiz
A v2.0.0 não passa nos health checks (bug de release).

## Como resolver
```bash
./lab.sh exercise rollback fix
# kubectl -n inc-rollback rollout undo deploy/shop            # volta à revisão anterior
# kubectl -n inc-rollback rollout undo deploy/shop --to-revision=1
```

## Como validar
`./lab.sh exercise rollback validate` → `/info` retorna `"version":"1.0.0"`, 3/3 pods Ready, histórico mostra nova revisão.

## Limpeza
`./lab.sh exercise rollback reset`

## Modelo de RCA (resumo)
Impacto: nenhum para usuários (v1 manteve o serviço); deploy bloqueado. Causa: bug na 2.0.0. Prevenção: testes de integração com health check, canary, `progressDeadlineSeconds` + alerta no pipeline.

## Perguntas de revisão
1. O que `maxSurge` e `maxUnavailable` controlam? 2. Como o `undo` funciona internamente? (reativa o ReplicaSet antigo.)
3. Rollback de banco de dados: o mesmo? (não; migrations backward-compatible.) 4. Rolling vs blue/green vs canary?
