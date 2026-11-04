# Service sem comunicação com os Pods

## Objetivo
Diagnosticar "Connection refused" para um Service com pods saudáveis.

## Contexto do incidente
Os pods do `web` estão 1/1 Running, mas qualquer chamada para o Service `web` falha.

## Como reproduzir
```bash
./lab.sh exercise service-no-endpoints
```
(o script já executa o teste do pod `client` e mostra a falha: `wget: can't connect ... Connection refused`)

## Investigação
```bash
NS=inc-service-no-endpoints
kubectl -n $NS get pods --show-labels                 # pods têm app=web
kubectl -n $NS get svc web -o wide                    # SELECTOR: app=webapp  <- diferente!
kubectl -n $NS get endpoints web                      # ENDPOINTS: <none>
kubectl -n $NS get endpointslices                     # mesmo dado, API nova
kubectl -n $NS describe svc web
```
**Como interpretar:** Service sem endpoints = nenhum pod **Ready** casa com o selector. Duas causas clássicas: selector/label divergente (este caso) ou pods não Ready (readiness falhando). `targetPort` errado dá endpoints preenchidos, mas conexão recusada.

## Causa-raiz
O selector do Service (`app: webapp`) não casa com o label dos pods (`app: web`).

## Como resolver
```bash
./lab.sh exercise service-no-endpoints fix
# kubectl -n inc-service-no-endpoints patch svc web -p '{"spec":{"selector":{"app":"web"}}}'
```

## Como validar
```bash
./lab.sh exercise service-no-endpoints validate   # endpoints preenchidos + wget com resposta JSON
```

## Limpeza
`./lab.sh exercise service-no-endpoints reset`

## Modelo de RCA (resumo)
Causa: erro de digitação em manifesto. Prevenção: Helm/Kustomize com labels gerados, lint (`kubeconform`), smoke test pós-deploy.

## Perguntas de entrevista
1. Como o Service encontra os pods? (selector → Endpoints/EndpointSlices.)
2. Endpoints preenchidos mas "connection refused": o que verificar? (targetPort, a app escutando 0.0.0.0, NetworkPolicy.)
3. Diferença entre ClusterIP, NodePort, LoadBalancer?
4. Como testar um Service sem expor? (`kubectl port-forward svc/web 8080:80`, ou pod efêmero.)
