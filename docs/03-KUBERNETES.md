# 03 — Kubernetes / AKS

Pré-requisito: `./lab.sh start k8s`. Todos os comandos abaixo funcionam no cluster `lab` (use `export PATH="$PWD/bin:$PATH"` para ter `kubectl`; contexto `kind-lab`). Para encurtar: `alias k='kubectl --context kind-lab'`; `export do='--dry-run=client -o yaml'`.

## 1. Arquitetura em 5 minutos
```
                ┌──────────────── Control plane (lab-control-plane) ────────────────┐
 kubectl ─────► │ kube-apiserver ─ etcd (estado)   kube-scheduler   controller-manager │
                └───────────────────────────────┬──────────────────────────────────┘
                         escolhe node ▼         │ kubelet busca o desejado
                ┌────────── Node (lab-worker) ──▼────────────────┐
                │ kubelet · container runtime (containerd) · kube-proxy │
                │   Pod(app) Pod(app)  ← containers + rede + volumes   │
                └───────────────────────────────────────────────────────┘
```
- **Cluster:** conjunto de nodes + control plane. **Node:** máquina (VM/container) que roda pods. **Pod:** menor unidade; 1+ containers que compartilham rede (mesmo IP) e volumes.
- **Controller loop:** você declara o estado desejado (YAML); controllers comparam com o real e corrigem continuamente. Por isso `kubectl delete pod` "ressuscita" o pod: o ReplicaSet recria.
- **Deployment → ReplicaSet → Pods:** o Deployment gerencia versões (rollout/rollback); cada versão é um ReplicaSet; o ReplicaSet mantém N pods.
- **Service:** IP/DNS estável + balanceamento para pods que casam com um *selector*. Tipos: ClusterIP (interno), NodePort (porta em todos os nodes; usada em `30080`), LoadBalancer (IP externo da nuvem).
- **Ingress:** regras HTTP (host/path) → Services; exige um *controller* (aqui ingress-nginx).
- **ConfigMap/Secret:** configuração e dados sensíveis (Secret é só base64, **não** criptografia por padrão).
- **Namespace:** isolamento lógico (quotas, RBAC, nomes).
- **requests/limits:** requests = reserva usada pelo scheduler; limits = teto. CPU acima do limit é *throttled*; memória acima do limit → **OOMKilled**.
- **Probes:** *liveness* (reiniciar se falhar), *readiness* (tirar do Service se falhar), *startup* (apps lentas para iniciar).

Veja tudo isso no app do lab: `kubectl --context kind-lab -n demo get deploy,rs,pods,svc,ingress,cm,secret`.

## 2. kubectl — comandos essenciais
Formato de cada item: **finalidade · sintaxe · exemplo · resultado esperado**.

### Descobrir o ambiente
| Comando | Finalidade / resultado |
|---|---|
| `kubectl config get-contexts` · `kubectl config use-context kind-lab` | lista/seleciona cluster. Esperado: `*` marca o contexto atual |
| `kubectl cluster-info` | endereços do API server e CoreDNS |
| `kubectl get nodes -o wide` | 2 nodes `Ready` (control-plane e worker), versão, IP interno |
| `kubectl get ns` | `default demo monitoring ingress-nginx kube-system ...` (+ `inc-*` nos exercícios) |
| `kubectl api-resources` / `kubectl explain deploy.spec.strategy` | recursos existentes / documentação de campos (ótimo na entrevista!) |

### Ver recursos (`get`)
Sintaxe: `kubectl [-n NS | -A] get <tipo> [nome] [-o wide|yaml|json|jsonpath=...] [-l label] [-w]`
```bash
kubectl -n demo get pods -o wide              # NAME READY STATUS RESTARTS AGE IP NODE
kubectl get pods -A                           # todos os namespaces
kubectl -n demo get deploy,rs,svc             # vários tipos
kubectl -n demo get pods -l app=lab-app       # por label
kubectl -n demo get pods -w                   # observa mudanças (Ctrl-C sai)
kubectl -n demo get deploy lab-app -o yaml    # manifesto completo, inclusive status
kubectl -n demo get pod -o jsonpath='{.items[*].metadata.name}'
kubectl get events -A --sort-by=.lastTimestamp | tail
```
- **READY** `1/1` = containers prontos/total. **STATUS**: `Running`, `Pending` (não agendado/baixando), `CrashLoopBackOff`, `ImagePullBackOff`, `Completed`, `Terminating`, `OOMKilled` (em `describe`).

### Investigar (`describe`)
`kubectl -n demo describe pod <pod>` — mostra Node, IP, imagem, env, probes, **Last State/Exit Code**, limits e, no fim, **Events** (a seção mais útil: falhas de scheduling, pull, probes). Também `describe node lab-worker` (Allocatable, Allocated resources, Conditions, Taints).

### Logs
```bash
kubectl -n demo logs deploy/lab-app                 # logs de um pod do deployment
kubectl -n demo logs -l app=lab-app --tail=20 --prefix   # de todos os pods, com prefixo do pod
kubectl -n demo logs <pod> -f --since=5m            # seguir últimos 5 min
kubectl -n demo logs <pod> --previous               # do container anterior (crash)
kubectl -n demo logs <pod> -c app                   # container específico
```
Esperado: linhas JSON do app: `{"ts": ..., "level": "INFO", "msg": "request", "status": 200, "duration_ms": 13.7, ...}`.

### Entrar/depurar
```bash
kubectl -n demo exec -it deploy/lab-app -- sh                  # shell no pod
kubectl -n demo exec deploy/lab-app -- python -c "print(1)"    # comando único
kubectl -n demo port-forward svc/lab-app 8081:80               # localhost:8081 -> Service (Ctrl-C encerra)
kubectl run dbg -it --rm --image=busybox:1.37 --image-pull-policy=IfNotPresent -- sh   # pod efêmero p/ testar rede/DNS
kubectl -n demo cp <pod>:/etc/hostname ./hostname.txt
kubectl debug node/lab-worker -it --image=busybox:1.37        # shell no node
```

### Criar/alterar
```bash
kubectl apply -f k8s/base/                       # declarativo (idempotente) — padrão em GitOps
kubectl diff -f k8s/base/                        # mostra o que mudaria
kubectl create deployment x --image=nginx:1.27-alpine --dry-run=client -o yaml   # gera YAML base
kubectl -n demo scale deploy/lab-app --replicas=3
kubectl -n demo set image deploy/lab-app app=lab-app:1.0.0
kubectl -n demo set env deploy/lab-app LOG_LEVEL=debug
kubectl -n demo set resources deploy/lab-app --limits=cpu=500m,memory=256Mi
kubectl -n demo edit deploy/lab-app              # editor (cuidado: não fica no Git)
kubectl -n demo patch svc lab-app -p '{"spec":{"type":"ClusterIP"}}'
kubectl -n demo delete pod <pod>                 # o ReplicaSet recria
kubectl -n demo rollout restart deploy/lab-app   # recria os pods gradualmente
```

### Uso de recursos (metrics-server)
`kubectl top nodes` · `kubectl top pods -A --sort-by=memory` → `CPU(cores)` em millicores (`5m`) e `MEMORY(bytes)` (`64Mi`). Leva ~1 min após subir o cluster.

### Rollout e rollback
```bash
kubectl -n demo rollout status deploy/lab-app          # espera concluir; sai com erro no timeout
kubectl -n demo rollout history deploy/lab-app         # REVISION  CHANGE-CAUSE
kubectl -n demo rollout history deploy/lab-app --revision=2
kubectl -n demo rollout undo deploy/lab-app            # volta à revisão anterior
kubectl -n demo rollout undo deploy/lab-app --to-revision=1
kubectl -n demo rollout pause|resume deploy/lab-app    # agrupar várias mudanças em 1 rollout
```
Prática guiada: `./lab.sh exercise rollback`.

### Manutenção de nodes
`kubectl cordon lab-worker` (não agendar novos) · `kubectl drain lab-worker --ignore-daemonsets --delete-emptydir-data` (evacuar) · `kubectl uncordon lab-worker`. Atenção: no lab há 1 worker, o drain deixa os pods `Pending` até o uncordon (bom exercício!).

## 3. Os manifests do lab, explicados
Abra [k8s/base/20-deployment.yaml](../k8s/base/20-deployment.yaml):
- `strategy.rollingUpdate: maxSurge 1, maxUnavailable 0` → sobe 1 pod novo; só remove um antigo quando o novo estiver Ready.
- `envFrom: configMapRef/secretRef` → variáveis vêm do ConfigMap `lab-app-config` e do Secret `lab-app-secret`.
- `resources: requests cpu 25m / memory 64Mi · limits cpu 250m / memory 192Mi`.
- `readinessProbe /readyz` e `livenessProbe /healthz` (HTTP).
- Annotations `prometheus.io/*` → o Prometheus descobre o pod.
Ver Secret e entender que é só base64: `kubectl -n demo get secret lab-app-secret -o jsonpath='{.data.API_TOKEN}' | base64 -d`.

## 4. Ingress
```bash
kubectl -n ingress-nginx get pods
kubectl -n demo get ingress
curl -s -H 'Host: lab.localtest.me' http://127.0.0.1:8080/api/hello
curl -s http://lab.localtest.me:8080/api/hello      # localtest.me resolve p/ 127.0.0.1 via DNS público
```
Fluxo: cliente → porta 8080 do host → node (hostPort 80) → pod do ingress-nginx → Service `lab-app` → pods.

## 5. Troubleshooting: tabela rápida
| Status / sintoma | Primeiro comando | Causas típicas |
|---|---|---|
| `Pending` | `describe pod` → Events | requests altos (Insufficient cpu/memory), taint, PVC não ligado, quota → exercício `pending-pod` |
| `ImagePullBackOff` / `ErrImagePull` | `describe pod` | tag errada, registry privado sem secret, sem rede → `imagepull-backoff` |
| `CrashLoopBackOff` | `logs --previous` + `describe` (Exit Code) | config ausente, erro de app, probe de liveness → `kubernetes-crashloop` |
| `OOMKilled` (exit 137) | `describe` → Last State | limit de memória baixo/leak → `oomkilled` |
| `Running` mas `0/1` Ready | `describe` → Readiness probe failed | probe/porta errada, app lenta no start → `rollback` |
| `CreateContainerConfigError` | `describe` | ConfigMap/Secret referenciado não existe |
| Service sem resposta | `get endpoints svc` | selector errado, pods não Ready, targetPort → `service-no-endpoints` |
| Nome não resolve | `exec ... nslookup`, logs do CoreDNS | dnsPolicy, CoreDNS caído, NetworkPolicy → `dns-failure` |
| `Evicted` | `describe pod` | pressão de memória/disco no node |
| `Terminating` preso | `get pod -o yaml` (finalizers) | finalizer pendente, node inacessível |
Sequência universal: `get pods -o wide` → `describe pod` → `logs [--previous]` → `get events` → `exec` / `port-forward` → `top`.

## 6. Kind (local) × AKS (Azure gerenciado)
| Aspecto | Kind (este lab) | AKS |
|---|---|---|
| Nodes | containers Docker (`lab-worker`) | VMs em *node pools* (VM Scale Sets) |
| Control plane | container; você é o dono | **gerenciado pela Azure** (grátis no tier Free; SLA no Standard) |
| Criar cluster | `kind create cluster` | `az aks create -g RG -n NOME --node-count 2` |
| Credenciais | kubeconfig automático `kind-lab` | `az aks get-credentials -g RG -n NOME` |
| Escalar nodes | recriar com mais nodes | `az aks scale` ou **Cluster Autoscaler** |
| Upgrade | recriar com outra imagem | `az aks upgrade` (cordon/drain automático por node) |
| Service LoadBalancer | pendente (sem cloud) | cria Azure Load Balancer + IP público |
| Ingress | ingress-nginx via hostPort | ingress-nginx / **Application Gateway Ingress** / App Routing add-on |
| Storage | `standard` (local-path) | StorageClasses de Azure Disk / Azure Files |
| Imagens | `kind load docker-image` | **Azure Container Registry (ACR)** + `az aks update --attach-acr` |
| Identidade | sem integração | **Microsoft Entra ID** + Azure RBAC for Kubernetes; Managed Identity / Workload Identity |
| Rede | kindnet | Azure CNI / kubenet / CNI Overlay; NSGs; Network Policies |
| Monitoramento | Prometheus/Grafana/Loki locais | **Container Insights** (Azure Monitor), Managed Prometheus/Grafana |
| Segredos | Secret simples | Secrets + **Key Vault CSI driver** |
| Custo | 0 | VMs dos nodes + LB + disco + logs |

**O que é idêntico:** API do Kubernetes e **todos os comandos `kubectl`** deste documento, manifests (Deployment, Service, Probes, requests/limits), troubleshooting de pods, rollout/rollback. **O que muda:** como se cria/atualiza o cluster, rede de entrada (LB/Ingress), identidade (Entra ID/Managed Identity), storage, registry e observabilidade — é o assunto que a entrevista de AKS costuma cobrar (veja [09](09-CLOUD-AWS-AZURE.md)).

Comandos `az` equivalentes (apenas para conhecer; **não são executados no lab**):
```bash
az aks create -g rg-lab -n aks-lab --node-count 2 --enable-managed-identity --generate-ssh-keys
az aks get-credentials -g rg-lab -n aks-lab
az aks nodepool add -g rg-lab --cluster-name aks-lab -n pool2 --node-count 1
az aks upgrade -g rg-lab -n aks-lab --kubernetes-version <versão>
```

## 7. Perguntas de entrevista (com resposta curta)
1. **O que acontece no `kubectl apply`?** API server valida/grava no etcd → controllers criam ReplicaSet/Pods → scheduler escolhe node → kubelet baixa imagem e inicia.
2. **Liveness vs readiness?** Liveness reinicia o container; readiness remove do balanceamento. Liveness agressiva demais derruba apps lentas.
3. **Como fazer deploy sem downtime?** RollingUpdate com readiness correta, `maxUnavailable: 0`, PodDisruptionBudget, graceful shutdown.
4. **O pod não sobe — por onde começa?** `describe pod` (Events) e `logs --previous`.
5. **Diferença Deployment × StatefulSet × DaemonSet × Job?**
6. **Como o scheduler decide?** filtra por requests/taints/affinity e pontua; usa *requests*, não uso real.
7. **Secret é seguro?** base64; proteja com RBAC, criptografia em repouso (KMS), Key Vault/Secrets Manager.
8. **HPA:** escala réplicas por métrica (CPU/memória/custom) usando metrics-server; precisa de `requests`.
