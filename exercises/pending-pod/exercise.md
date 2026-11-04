# Pod em Pending (recursos insuficientes)

## Objetivo
Ler eventos do scheduler (`FailedScheduling`) e entender allocatable vs requests.

## Contexto do incidente
Um novo serviço `bigapp` fica `Pending` indefinidamente; nenhum container foi criado.

## Como reproduzir
`./lab.sh exercise pending-pod`

## Investigação
```bash
NS=inc-pending-pod
kubectl -n $NS get pods                                       # Pending, sem node atribuído
kubectl -n $NS describe pod -l app=bigapp | tail -8           # 0/2 nodes are available: 1 Insufficient cpu, 1 Insufficient memory (+ taints)
kubectl describe nodes | grep -A8 "Allocatable"               # capacidade real
kubectl describe nodes | grep -A10 "Allocated resources"      # já reservado
kubectl -n $NS get deploy bigapp -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```
**Como interpretar:** `Pending` + `FailedScheduling` = o scheduler não achou node. Causas: requests maiores que o node, nodeSelector/affinity/taints sem match, PVC não ligado, quota do namespace.

## Causa-raiz
`requests: cpu 64 / memory 256Gi` — absurdamente acima do que qualquer node oferece.

## Como resolver
`./lab.sh exercise pending-pod fix` (= `kubectl set resources deploy/bigapp --requests=cpu=50m,memory=64Mi`)

## Como validar
`./lab.sh exercise pending-pod validate` → Running em um node.

## Limpeza
`./lab.sh exercise pending-pod reset`

## Modelo de RCA (resumo)
Causa: requests mal dimensionados (unidade/valor). Em nuvem: o Cluster Autoscaler tentaria criar nodes (e falharia se nenhum tipo comportar). Prevenção: LimitRange/ResourceQuota, revisão de manifestos.

## Perguntas de entrevista
1. O scheduler usa requests ou uso real? (requests.) 2. Pending por PVC: como diagnosticar?
3. O que são taints/tolerations? 4. Como o Cluster Autoscaler/Karpenter reagem a Pending?
