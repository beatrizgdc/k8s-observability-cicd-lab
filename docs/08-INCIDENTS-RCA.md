# 08 — Troubleshooting e Incidentes (com RCA)

> Este arquivo é **gerado** por `scripts/build-incidents-doc.sh` a partir de `exercises/*/exercise.md`.
> Edite os guias em `exercises/<nome>/exercise.md` e rode o script novamente.

Cada incidente é **isolado** (namespace próprio `inc-<nome>` ou container próprio) e **reversível** (`reset`).
Comandos de qualquer exercício:

```bash
./lab.sh exercise list
./lab.sh exercise <nome>            # reproduz o incidente
./lab.sh exercise <nome> fix        # aplica a correção
./lab.sh exercise <nome> validate   # confirma a recuperação
./lab.sh exercise <nome> reset      # remove tudo que o exercício criou
./lab.sh exercise <nome> guide      # imprime o roteiro no terminal
```

**Método geral de investigação (use em todos):**
1. *Qual o sintoma e desde quando?* (alerta, usuário, métrica)  2. *O que mudou?* (deploy, config, tráfego)
3. *Qual o escopo?* (um pod, todos, um node, um serviço)  4. *Onde está o primeiro erro?* (eventos, logs, métricas)
5. *Mitigar primeiro, corrigir depois.*  6. *Validar com a mesma métrica que alertou.*  7. *Registrar o RCA.*

## Sumário
1. [`dns-failure` — Problema de resolução DNS](#dns-failure)
2. [`high-cpu` — Aplicação com CPU elevada (throttling)](#high-cpu)
3. [`high-latency` — Aplicação com latência elevada](#high-latency)
4. [`http-500` — Aplicação retornando HTTP 500](#http-500)
5. [`imagepull-backoff` — ImagePullBackOff (tag de imagem errada)](#imagepull-backoff)
6. [`jenkins-pipeline-fail` — Pipeline Jenkins com falha](#jenkins-pipeline-fail)
7. [`kubernetes-crashloop` — Pod em CrashLoopBackOff (variável de ambiente ausente)](#kubernetes-crashloop)
8. [`linux-cpu` — Linux: processos consumindo CPU](#linux-cpu)
9. [`linux-disk` — Linux: disco cheio](#linux-disk)
10. [`linux-dns` — Linux: "a internet caiu?" — DNS vs rede](#linux-dns)
11. [`linux-port` — Linux: porta já em uso](#linux-port)
12. [`oomkilled` — Container morto por OOMKilled](#oomkilled)
13. [`pending-pod` — Pod em Pending (recursos insuficientes)](#pending-pod)
14. [`rollback` — Deploy com versão incorreta — rollout travado e rollback](#rollback)
15. [`service-no-endpoints` — Service sem comunicação com os Pods](#service-no-endpoints)
16. [`vulnerable-image` — Imagem Docker com vulnerabilidades](#vulnerable-image)

---

<a id="dns-failure"></a>

## 1. Problema de resolução DNS

### Objetivo
Separar "rede quebrada" de "DNS quebrado" dentro do cluster e entender o CoreDNS/`resolv.conf` dos pods.

### Contexto do incidente
Um pod não resolve nenhum nome (`nslookup` dá timeout) enquanto outros pods do mesmo namespace funcionam.

### Como reproduzir
```bash
./lab.sh exercise dns-failure
```
Cria `client-ok` (DNS padrão) e `client-broken` (`dnsPolicy: None` apontando para 10.255.255.1, que não existe).

### Investigação
```bash
NS=inc-dns-failure
kubectl -n $NS exec client-ok -- nslookup alvo.$NS.svc.cluster.local        # funciona
kubectl -n $NS exec client-broken -- nslookup -timeout=3 alvo.$NS.svc.cluster.local   # "no servers could be reached"
kubectl -n $NS exec client-ok -- cat /etc/resolv.conf       # nameserver 10.96.0.10 (kube-dns) + search ...svc.cluster.local
kubectl -n $NS exec client-broken -- cat /etc/resolv.conf   # nameserver 10.255.255.1
kubectl -n kube-system get pods -l k8s-app=kube-dns         # CoreDNS saudável?
kubectl -n kube-system get svc kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
kubectl -n $NS get pod client-broken -o jsonpath='{.spec.dnsPolicy}{"\n"}'
```
**Como interpretar:** CoreDNS saudável + `client-ok` resolvendo ⇒ problema local do pod. O `resolv.conf` do pod quebrado aponta para outro servidor.

### Causa-raiz
`dnsPolicy: None` com `dnsConfig` apontando para um nameserver inexistente.

### Como resolver
```bash
./lab.sh exercise dns-failure fix     # recria o pod com a política padrão ClusterFirst
```
(`dnsPolicy` não pode ser alterado em pod existente; recria-se o pod/Deployment.)

### Como validar
`./lab.sh exercise dns-failure validate` → `nslookup` retorna o ClusterIP do Service.

### Limpeza
`./lab.sh exercise dns-failure reset`

### Modelo de RCA (resumo)
Causa: configuração de DNS customizada incorreta. Prevenção: não sobrescrever dnsPolicy sem necessidade; teste de DNS no smoke test.

### Perguntas de entrevista
1. Qual o FQDN de um Service? (`<svc>.<ns>.svc.cluster.local`.)
2. O que o `ndots:5` provoca? (várias consultas com search domains antes do nome absoluto → latência.)
3. Se o CoreDNS caísse, o que falharia? (descoberta por nome; IPs diretos continuam.)
4. Como depurar com um pod efêmero? (`kubectl run -it --rm dbg --image=busybox:1.37 -- sh`.)

---

<a id="high-cpu"></a>

## 2. Aplicação com CPU elevada (throttling)

### Objetivo
Identificar consumo de CPU por pod, entender limit/throttling e correlacionar com latência.

### Contexto do incidente
Um pod `burner` está lento. O time de monitoramento notou CPU "colada" em 200m.

### Como reproduzir
```bash
./lab.sh exercise high-cpu
```
Pod com `limits.cpu: 200m`; o script chama `/cpu?seconds=900` (um loop que consome 1 core por 15 min).

### Investigação
```bash
NS=inc-high-cpu
kubectl -n $NS top pod                         # após ~60s: CPU(cores) ≈ 200m (exatamente o limit)
kubectl -n $NS logs deploy/burner | tail -3    # "consumo de CPU iniciado"
kubectl -n $NS exec deploy/burner -- cat /sys/fs/cgroup/cpu.stat    # nr_throttled / throttled_usec crescendo
kubectl -n $NS exec deploy/burner -- python -c "print(open('/proc/loadavg').read())"
```
No Prometheus: `rate(container_cpu_usage_seconds_total{namespace="inc-high-cpu",container="app"}[1m])` (≈0.2) e a razão de `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` (alta). Alerta `ContainerCpuThrottled` dispara em ~1–2 min.

**Como interpretar:** uso encostado no limit + `nr_throttled` crescendo = o container *queria* mais CPU e o kernel o freou. Latência das requisições normais sobe (veja `/api/hello` demorando).

### Causa-raiz
Uma requisição (`/cpu`) inicia trabalho CPU-bound sem controle no mesmo processo que atende tráfego.

### Como resolver
```bash
./lab.sh exercise high-cpu fix     # rollout restart: mitigação imediata
```
Correção real: isolar trabalho pesado (fila/worker), limitar concorrência, otimizar. Subir o limit só adia o problema; HPA ajuda com carga legítima, não com loop descontrolado.

### Como validar
`./lab.sh exercise high-cpu validate` → `kubectl top pod` volta para poucos millicores.

### Limpeza
`./lab.sh exercise high-cpu reset`

### Modelo de RCA (resumo)
Causa: processamento CPU-bound sem proteção. Detecção: alerta de throttling. Prevenção: rate limit, limites de timeout, perf test, HPA.

### Perguntas de entrevista
1. O que significa throttling? (CFS quota: o container só roda `limit` ms a cada 100 ms.)
2. `top` do node mostra CPU baixa mas o pod está lento. Por quê? (throttling por limit.)
3. Request vs limit de CPU: efeito no scheduling e na execução?
4. Quando usar HPA e em que métrica?

---

<a id="high-latency"></a>

## 3. Aplicação com latência elevada

### Objetivo
Medir latência (p50/p95/p99), localizar onde está o tempo gasto e correlacionar métrica, log e trace.

### Contexto do incidente
Usuários reclamam de lentidão em `/api/work`. Sem erros, sem restart: "está só devagar".

### Como reproduzir
```bash
./lab.sh start observability
./lab.sh exercise high-latency
```
`FAULT_LATENCY_MS=1500` via ConfigMap em `inc-high-latency`, com tráfego contínuo.

### Investigação
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

### Causa-raiz
Latência artificial injetada por configuração (`FAULT_LATENCY_MS`), simulando uma dependência lenta.

### Como resolver
```bash
./lab.sh exercise high-latency fix     # ConfigMap = 0 + rollout restart
```

### Como validar
`./lab.sh exercise high-latency validate`; no Grafana o p95 volta a ~50 ms.

### Limpeza
`./lab.sh exercise high-latency reset`

### Modelo de RCA (resumo)
Causa: dependência/config lenta. Detecção: alerta p95. Prevenção: timeouts + circuit breaker, SLO de latência, tracing.

### Perguntas de entrevista
1. Por que usar percentis e não média? (média esconde cauda.)
2. Latência alta: como saber se é CPU, I/O, rede ou dependência?
3. O que é um trace/span e quando é melhor que logs?
4. Qual a diferença entre latência e throughput (traffic)?

---

<a id="http-500"></a>

## 4. Aplicação retornando HTTP 500

### Objetivo
Investigar aumento de erros 5xx usando logs, métricas (RED/Golden Signals) e alerta; entender que ConfigMap só vale após restart.

### Contexto do incidente
Depois de uma mudança de configuração, ~40% das chamadas a `/api/work` falham com HTTP 500. Pods continuam Ready (o health check não pega o problema).

### Como reproduzir
```bash
./lab.sh start observability      # recomendado (Grafana/Loki); o incidente roda mesmo sem
./lab.sh exercise http-500
```
Cria `inc-http-500` com `api` (2 réplicas, `FAULT_ERROR_RATE=0.4` vindo de um ConfigMap) e `load` (gerador de tráfego).

### Investigação
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

### Causa-raiz
Valor incorreto (`FAULT_ERROR_RATE=0.4`) publicado na configuração; a app o lê no start.

### Como resolver
```bash
./lab.sh exercise http-500 fix
# kubectl -n inc-http-500 patch configmap api-config --type merge -p '{"data":{"FAULT_ERROR_RATE":"0"}}'
# kubectl -n inc-http-500 rollout restart deploy/api     # SEM isto, os pods antigos mantêm o valor!
```

### Como validar
`./lab.sh exercise http-500 validate` → 5 respostas 200. Em ~2 min a taxa de 5xx cai a 0 no Grafana e o alerta resolve.

### Limpeza
`./lab.sh exercise http-500 reset`

### Modelo de RCA (resumo)
Causa: configuração inválida em produção. Detecção: alerta HighErrorRate. Correção: rollback da config + restart. Prevenção: canary/rollout gradual, validação de config, SLO com burn-rate.

### Perguntas de entrevista
1. Como diferenciar erro de aplicação (5xx) de erro do cliente (4xx)?
2. Readiness OK e 500 alto: por que o K8s não resolve sozinho? (probe não cobre a lógica.)
3. Por que mudar o ConfigMap não alterou o comportamento? (env vars só na criação do container; volume monta atualiza, env não.)
4. O que é SLI/SLO/error budget? Qual SLI você usaria aqui?

---

<a id="imagepull-backoff"></a>

## 5. ImagePullBackOff (tag de imagem errada)

### Objetivo
Reconhecer ErrImagePull/ImagePullBackOff e achar a causa em `describe`/Events.

### Contexto do incidente
Novo deploy do `checkout` nunca sobe; o pod mostra `ImagePullBackOff`.

### Como reproduzir
`./lab.sh exercise imagepull-backoff`

### Investigação
```bash
NS=inc-imagepull-backoff
kubectl -n $NS get pods                                      # ErrImagePull -> ImagePullBackOff
kubectl -n $NS describe pod -l app=checkout | tail -15       # Events: Failed to pull image "lab-app:1.0.O" ... not found / pull access denied
kubectl -n $NS get deploy checkout -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```
**Como interpretar:** a mensagem de Events diz *por que*: tag inexistente, repositório privado sem `imagePullSecrets` (`unauthorized`), registry inacessível (timeout), arquitetura errada. Aqui: a tag tem a letra **O** em vez de **0**.

### Causa-raiz
Erro de digitação na tag da imagem.

### Como resolver
`./lab.sh exercise imagepull-backoff fix` (= `kubectl set image deploy/checkout app=lab-app:1.0.0`)

### Como validar
`./lab.sh exercise imagepull-backoff validate` → pod Running.

### Limpeza
`./lab.sh exercise imagepull-backoff reset`

### Modelo de RCA (resumo)
Causa: tag errada. Prevenção: pipeline que gera a tag (não digitar), verificação de existência da imagem antes do deploy, tags imutáveis/digest.

### Perguntas de entrevista
1. ErrImagePull vs ImagePullBackOff? 2. Como puxar de ECR/ACR privado? (imagePullSecrets, IAM/managed identity.)
3. Por que evitar `latest`? 4. `imagePullPolicy` Always/IfNotPresent/Never?

---

<a id="jenkins-pipeline-fail"></a>

## 6. Pipeline Jenkins com falha

### Objetivo
Ler o Console Output do Jenkins, achar o estágio que falhou e ligar a falha ao commit responsável.

### Contexto do incidente
O último commit ("internacionaliza mensagem") fez a pipeline `lab-app` ficar vermelha. Nada foi implantado.

### Como reproduzir
```bash
./lab.sh start cicd            # Jenkins em http://127.0.0.1:8088 (admin/admin)
./lab.sh exercise jenkins-pipeline-fail
```
O script faz um commit no repositório local `.data/app-repo` (o que o Jenkins faz checkout) e dispara a pipeline.

### Investigação
- Jenkins → job `lab-app` → build vermelho → **Stage View**: o estágio `Test` está vermelho; os seguintes estão "cinza" (não executaram).
- **Console Output**: procure `FAILED` / `AssertionError`:
  `FAILED tests/test_app.py::test_hello ... 1 failed, 10 passed`
- **Test Result** (plugin JUnit) mostra o teste e o stack trace.
```bash
git -C .data/app-repo log --oneline -3          # qual commit?
git -C .data/app-repo show HEAD                 # o que mudou (olá do lab -> hello from lab)
./lab.sh pipeline run                           # reexecuta e mostra o log no terminal
```
**Como interpretar:** Checkout/Build OK ⇒ ambiente e dependências bem; falha em Test ⇒ regressão de código. Pipeline parou antes de Docker Build/Deploy: nada ruim chegou ao cluster (o objetivo do CI).

### Causa-raiz
Mudança na mensagem sem atualizar o teste que a valida.

### Como resolver
```bash
./lab.sh exercise jenkins-pipeline-fail fix       # git revert do commit ruim
./lab.sh exercise jenkins-pipeline-fail validate  # roda a pipeline: SUCCESS
```
(Alternativa: corrigir o teste e commitar.)

### Outras falhas para provocar (veja docs/05-JENKINS-CICD.md)
`flake8` (estilo), Security Scan (`TRIVY_FAIL_ON`), Docker Build (Dockerfile quebrado), Deploy (imagem inexistente → rollback automático).

### Limpeza
`./lab.sh exercise jenkins-pipeline-fail reset` (reverte o commit se ainda estiver lá).

### Modelo de RCA (resumo)
Causa: commit sem teste correspondente. Detecção: CI. Prevenção: rodar testes localmente/pre-commit, PR obrigatório com CI verde.

### Perguntas de entrevista
1. Diferença entre CI e CD? Onde o rollback entra?
2. Como investigar uma pipeline que "funcionava ontem"? (diff de commits, versões de dependências, estado do agente/cache.)
3. Declarative vs Scripted pipeline?
4. Como evitar que segredos apareçam no log? (credentials binding, `set +x`.)

---

<a id="kubernetes-crashloop"></a>

## 7. Pod em CrashLoopBackOff (variável de ambiente ausente)

### Objetivo
Aprender o fluxo `get → describe → logs --previous` para pods que reiniciam em loop.

### Contexto do incidente
Após um deploy, o `orders-api` nunca fica Ready. O time diz: "funcionava no ambiente de testes". O pod está em `CrashLoopBackOff`.

### Como reproduzir
```bash
./lab.sh exercise kubernetes-crashloop
```
Cria o namespace `inc-kubernetes-crashloop` com um Deployment que exige a variável `DATABASE_URL` (que não é definida).

### Investigação
```bash
NS=inc-kubernetes-crashloop
kubectl -n $NS get pods                                  # STATUS CrashLoopBackOff/Error, RESTARTS subindo
kubectl -n $NS describe pod -l app=orders-api            # veja "Last State", "Exit Code" e a seção Events
kubectl -n $NS logs deploy/orders-api --previous         # log da execução ANTERIOR (a que morreu)
kubectl -n $NS get events --sort-by=.lastTimestamp | tail
```
**Como interpretar**
- `Exit Code: 3` com `Reason: Error` = o processo saiu por conta própria (não foi OOM nem kill). Código 137 seria SIGKILL/OOM; 1/2/3 geralmente é erro da aplicação.
- `logs --previous` mostra: `variável obrigatória DATABASE_URL ausente; encerrando`.
- O backoff cresce (10s, 20s, 40s… até 5 min): por isso "CrashLoop" parece demorar.

### Causa-raiz
Configuração ausente: o Deployment não injeta `DATABASE_URL`. Não é problema de imagem, rede nem recurso.

### Como resolver
```bash
./lab.sh exercise kubernetes-crashloop fix
# equivalente a:
kubectl -n inc-kubernetes-crashloop set env deploy/orders-api DATABASE_URL=postgres://db.exemplo:5432/orders
```
Em produção, o valor viria de um Secret/ConfigMap (`envFrom`), não de um valor literal.

### Como validar
```bash
./lab.sh exercise kubernetes-crashloop validate     # rollout concluído, pod 1/1 Running
kubectl -n inc-kubernetes-crashloop get pods
```

### Limpeza
```bash
./lab.sh exercise kubernetes-crashloop reset
```

### Modelo de RCA (resumo)
- **Impacto:** serviço indisponível desde o deploy X. **Detecção:** alerta de pods não Ready.
- **Causa:** variável DATABASE_URL não incluída no manifesto do deploy. **Correção:** adicionada. **Prevenção:** validação de config no CI, `kubectl diff`, checklist de variáveis obrigatórias.

### Perguntas de entrevista
1. Qual a diferença entre `CrashLoopBackOff` e `Error`? (Error = última saída; CrashLoopBackOff = o kubelet está esperando o backoff antes de reiniciar.)
2. Por que usar `--previous`? E se o container nunca chegou a iniciar? (Veja `describe` → Events.)
3. Cite 4 causas de CrashLoopBackOff. (config ausente, comando errado, OOM, liveness probe falhando, dependência indisponível.)
4. Como saber se foi OOM? (`Reason: OOMKilled`, exit 137.)

---

<a id="linux-cpu"></a>

## 8. Linux: processos consumindo CPU

### Objetivo
Achar rapidamente quem consome CPU e entender load average, `nice` e sinais.

### Contexto do incidente
O servidor (sua máquina) está lento e o ventilador disparou.

### Como reproduzir
`./lab.sh exercise linux-cpu` — inicia 2 loops `lab-cpuhog` (nice 10, 100% de 2 núcleos cada um).

### Investigação
```bash
uptime                                            # load average maior que o nº de CPUs ($(nproc)) = fila de execução
top -o %CPU                                       # (q sai) ordene por CPU; 'H' mostra threads; '1' mostra por núcleo
ps -eo pid,ppid,ni,pcpu,etime,cmd --sort=-pcpu | head -5
pgrep -af lab-cpuhog
cat /proc/<PID>/status | grep -E "State|Threads"
```
**Como interpretar:** `%CPU` ~100 por processo = 1 núcleo cheio. `NI 10` = prioridade baixa (cede CPU a outros). `load average` (1/5/15 min) sobe com processos prontos para rodar. `us` alto no `top` = CPU em user space; `sy` alto = kernel; `wa` alto = esperando disco (não é CPU real).

### Causa-raiz
Dois processos em loop infinito (`while :; do :; done`).

### Como resolver
```bash
kill <PID>          # SIGTERM (pede para encerrar)
kill -9 <PID>       # SIGKILL (último recurso)
# ou o atalho do lab:
./lab.sh exercise linux-cpu fix
```

### Como validar
`./lab.sh exercise linux-cpu validate` e `uptime` (load cai gradualmente).

### Modelo de RCA / perguntas
Causa: loop sem sleep. Prevenção: limites (cgroups/ulimit), alertas de CPU/load. Perguntas: load alto com CPU baixa? (I/O wait ou D-state.) Diferença entre `kill` e `kill -9`? O que é processo zumbi?

---

<a id="linux-disk"></a>

## 9. Linux: disco cheio

### Objetivo
Diagnosticar "No space left on device" com `df`, `du`, `find` (e inodes).

### Contexto do incidente
A aplicação para de gravar logs e dá erro de escrita. (O exercício usa um container com `tmpfs` de 64 MB — o disco real da sua máquina não é afetado.)

### Como reproduzir
`./lab.sh exercise linux-disk` (container `lab-diskfull`).

### Investigação
```bash
docker exec lab-diskfull df -h /data                   # Use% alto
docker exec lab-diskfull df -i /data                   # inodes (arquivos) — também podem esgotar
docker exec lab-diskfull du -ah /data | sort -h | tail # maiores arquivos/diretórios
docker exec lab-diskfull find /data -type f -size +5M
# no seu host, o mesmo raciocínio:  df -h ;  du -xh / --max-depth=1 2>/dev/null | sort -h | tail ;  sudo find / -xdev -size +500M
```
**Como interpretar:** `df` diz *quanto* está usado por filesystem; `du` diz *onde*. `Use% 100` = cheio. Se `df` mostra espaço mas grava falha, olhe `df -i`. Arquivo apagado mas ainda aberto por processo não libera espaço (`lsof +L1`).

### Causa-raiz
Um `app.log` de 40 MB nunca rotacionado.

### Como resolver
`./lab.sh exercise linux-disk fix` (= `: > app.log`, truncar libera espaço mesmo com o arquivo aberto). Em produção: logrotate, retenção, enviar logs ao Loki.

### Como validar
`./lab.sh exercise linux-disk validate`.

### Limpeza / Perguntas
`./lab.sh exercise linux-disk reset`. Perguntas: `rm` vs truncar arquivo aberto? Como achar quem segura um arquivo deletado? Como prevenir (logrotate, alertas em 80%)?

---

<a id="linux-dns"></a>

## 10. Linux: "a internet caiu?" — DNS vs rede

### Objetivo
Separar falha de conectividade (IP) de falha de resolução de nomes.

### Contexto do incidente
"Não consigo acessar nada!" — mas o link está de pé.

### Como reproduzir
`./lab.sh exercise linux-dns` — container com resolvedor inexistente (10.255.255.1).

### Investigação
```bash
ping -c1 <IP do gateway>                  # funciona => rede OK
nslookup example.com                      # falha => DNS
dig example.com +time=2 +tries=1          # detalhes: status, servidor consultado
dig @1.1.1.1 example.com                  # testa outro resolvedor (precisa de internet)
cat /etc/resolv.conf                      # qual nameserver?
resolvectl status                         # no host com systemd-resolved
ip route                                  # rota padrão (ip route get 8.8.8.8)
```
**Como interpretar:** ping por IP OK + nome falha = DNS. `connection timed out; no servers could be reached` = resolvedor inacessível. `NXDOMAIN` = o nome não existe (resolvedor ok). `SERVFAIL` = o resolvedor falhou ao resolver.

### Causa-raiz
`/etc/resolv.conf` apontando para um servidor DNS inexistente.

### Como resolver
`./lab.sh exercise linux-dns fix` (recria o container com o DNS padrão). No host: corrigir `resolvectl dns <iface> <ip>` / DHCP.

### Como validar
`./lab.sh exercise linux-dns validate` (requer internet nesta etapa).

### Limpeza / Perguntas
`./lab.sh exercise linux-dns reset`. Perguntas: como o `traceroute`/`mtr` ajuda? Qual a ordem de resolução (`/etc/nsswitch.conf`, `/etc/hosts`)? TTL e cache?

---

<a id="linux-port"></a>

## 11. Linux: porta já em uso

### Objetivo
Descobrir qual processo ocupa uma porta com `ss`, e liberar com segurança.

### Contexto do incidente
O deploy da nova versão falha: `OSError: [Errno 98] Address already in use` na porta 8099.

### Como reproduzir
`./lab.sh exercise linux-port` (sobe um servidor `lab-port-holder` na 8099 e tenta subir outro).

### Investigação
```bash
ss -ltnp 'sport = :8099'          # -l listening, -t TCP, -n numérico, -p processo (PID/nome)
ps -fp <PID>                      # quem é, quem iniciou, há quanto tempo
curl -sI http://127.0.0.1:8099    # o que está respondendo?
nc -zv 127.0.0.1 8099             # a porta aceita conexão?
```
**Como interpretar:** `LISTEN 127.0.0.1:8099 users:(("python3",pid=...))`. `127.0.0.1` = só local; `0.0.0.0`/`*` = todas as interfaces.

### Causa-raiz
Instância antiga (ou outro processo) ainda escutando a porta.

### Como resolver
`kill <PID>` (ou `./lab.sh exercise linux-port fix`). Confirme que o processo é o que você pensa antes de matar.

### Como validar
`ss -ltn 'sport = :8099'` sem resultado; `./lab.sh exercise linux-port validate`.

### Limpeza / Perguntas
`./lab.sh exercise linux-port reset`. Perguntas: TIME_WAIT é problema? `ss` vs `netstat`? Como achar o dono sem `-p` (sem root)? `SO_REUSEADDR`?

---

<a id="oomkilled"></a>

## 12. Container morto por OOMKilled

### Objetivo
Distinguir "app com bug" de "limit de memória baixo" e ler `OOMKilled`/exit code 137.

### Contexto do incidente
O serviço `leaky` reinicia sozinho após receber certas requisições; clientes veem conexões cortadas.

### Como reproduzir
```bash
./lab.sh exercise oomkilled
```
Deployment com `limits.memory: 100Mi`; o script chama `/memory?mb=150`, que aloca 150 MB e os mantém.

### Investigação
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

### Causa-raiz
A requisição consome mais memória (150 MB + base ≈ 60 MB) que o limit (100 Mi). Pode ser limit subdimensionado **ou** vazamento/pico no código; é preciso medir antes de aumentar.

### Como resolver
```bash
./lab.sh exercise oomkilled fix
# equivalente a: kubectl -n inc-oomkilled set resources deploy/leaky --limits=memory=300Mi --requests=memory=128Mi
```
Aumentar o limit é **mitigação**. A correção real é achar por que o app precisa de tanta memória (profiling, paginação, cache sem limite).

### Como validar
```bash
./lab.sh exercise oomkilled validate     # chama /memory?mb=150 novamente: sem OOM; RESTARTS do pod novo = 0
```

### Limpeza
`./lab.sh exercise oomkilled reset`

### Modelo de RCA (resumo)
Causa: pico de memória > limit. Detecção: alerta `ContainerMemoryNearLimit` (>85% do limit) deveria ter avisado antes. Prevenção: alerta de saturação, teste de carga, requests = uso típico, limit = pico + margem.

### Perguntas de entrevista
1. Qual a diferença entre request e limit de memória? (request = reserva p/ scheduling; limit = teto, estourou → OOMKilled.)
2. Por que CPU acima do limit é "throttled" e memória é "killed"? (CPU é compressível; memória não.)
3. O que é a QoS class (Guaranteed/Burstable/BestEffort) e como influencia evictions?
4. Como diferenciar OOMKilled de Evicted? (`describe`: Reason; Evicted aparece no status do Pod com mensagem do node pressure.)

---

<a id="pending-pod"></a>

## 13. Pod em Pending (recursos insuficientes)

### Objetivo
Ler eventos do scheduler (`FailedScheduling`) e entender allocatable vs requests.

### Contexto do incidente
Um novo serviço `bigapp` fica `Pending` indefinidamente; nenhum container foi criado.

### Como reproduzir
`./lab.sh exercise pending-pod`

### Investigação
```bash
NS=inc-pending-pod
kubectl -n $NS get pods                                       # Pending, sem node atribuído
kubectl -n $NS describe pod -l app=bigapp | tail -8           # 0/2 nodes are available: 1 Insufficient cpu, 1 Insufficient memory (+ taints)
kubectl describe nodes | grep -A8 "Allocatable"               # capacidade real
kubectl describe nodes | grep -A10 "Allocated resources"      # já reservado
kubectl -n $NS get deploy bigapp -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
```
**Como interpretar:** `Pending` + `FailedScheduling` = o scheduler não achou node. Causas: requests maiores que o node, nodeSelector/affinity/taints sem match, PVC não ligado, quota do namespace.

### Causa-raiz
`requests: cpu 64 / memory 256Gi` — absurdamente acima do que qualquer node oferece.

### Como resolver
`./lab.sh exercise pending-pod fix` (= `kubectl set resources deploy/bigapp --requests=cpu=50m,memory=64Mi`)

### Como validar
`./lab.sh exercise pending-pod validate` → Running em um node.

### Limpeza
`./lab.sh exercise pending-pod reset`

### Modelo de RCA (resumo)
Causa: requests mal dimensionados (unidade/valor). Em nuvem: o Cluster Autoscaler tentaria criar nodes (e falharia se nenhum tipo comportar). Prevenção: LimitRange/ResourceQuota, revisão de manifestos.

### Perguntas de entrevista
1. O scheduler usa requests ou uso real? (requests.) 2. Pending por PVC: como diagnosticar?
3. O que são taints/tolerations? 4. Como o Cluster Autoscaler/Karpenter reagem a Pending?

---

<a id="rollback"></a>

## 14. Deploy com versão incorreta — rollout travado e rollback

### Objetivo
Praticar `rollout status/history/undo` e entender como `maxUnavailable: 0` + readiness protegem o serviço.

### Contexto do incidente
Release 2.0.0 do `shop` foi aplicada. Alguns minutos depois, o pipeline de deploy "pendura" em *Waiting for rollout to finish*.

### Como reproduzir
```bash
./lab.sh exercise rollback
```
Aplica v1.0.0 (3 réplicas, estável) e depois v2.0.0 com `FAIL_HEALTH=1` (health checks respondem 503).

### Investigação
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

### Causa-raiz
A v2.0.0 não passa nos health checks (bug de release).

### Como resolver
```bash
./lab.sh exercise rollback fix
# kubectl -n inc-rollback rollout undo deploy/shop            # volta à revisão anterior
# kubectl -n inc-rollback rollout undo deploy/shop --to-revision=1
```

### Como validar
`./lab.sh exercise rollback validate` → `/info` retorna `"version":"1.0.0"`, 3/3 pods Ready, histórico mostra nova revisão.

### Limpeza
`./lab.sh exercise rollback reset`

### Modelo de RCA (resumo)
Impacto: nenhum para usuários (v1 manteve o serviço); deploy bloqueado. Causa: bug na 2.0.0. Prevenção: testes de integração com health check, canary, `progressDeadlineSeconds` + alerta no pipeline.

### Perguntas de entrevista
1. O que `maxSurge` e `maxUnavailable` controlam? 2. Como o `undo` funciona internamente? (reativa o ReplicaSet antigo.)
3. Rollback de banco de dados: o mesmo? (não; migrations backward-compatible.) 4. Rolling vs blue/green vs canary?

---

<a id="service-no-endpoints"></a>

## 15. Service sem comunicação com os Pods

### Objetivo
Diagnosticar "Connection refused" para um Service com pods saudáveis.

### Contexto do incidente
Os pods do `web` estão 1/1 Running, mas qualquer chamada para o Service `web` falha.

### Como reproduzir
```bash
./lab.sh exercise service-no-endpoints
```
(o script já executa o teste do pod `client` e mostra a falha: `wget: can't connect ... Connection refused`)

### Investigação
```bash
NS=inc-service-no-endpoints
kubectl -n $NS get pods --show-labels                 # pods têm app=web
kubectl -n $NS get svc web -o wide                    # SELECTOR: app=webapp  <- diferente!
kubectl -n $NS get endpoints web                      # ENDPOINTS: <none>
kubectl -n $NS get endpointslices                     # mesmo dado, API nova
kubectl -n $NS describe svc web
```
**Como interpretar:** Service sem endpoints = nenhum pod **Ready** casa com o selector. Duas causas clássicas: selector/label divergente (este caso) ou pods não Ready (readiness falhando). `targetPort` errado dá endpoints preenchidos, mas conexão recusada.

### Causa-raiz
O selector do Service (`app: webapp`) não casa com o label dos pods (`app: web`).

### Como resolver
```bash
./lab.sh exercise service-no-endpoints fix
# kubectl -n inc-service-no-endpoints patch svc web -p '{"spec":{"selector":{"app":"web"}}}'
```

### Como validar
```bash
./lab.sh exercise service-no-endpoints validate   # endpoints preenchidos + wget com resposta JSON
```

### Limpeza
`./lab.sh exercise service-no-endpoints reset`

### Modelo de RCA (resumo)
Causa: erro de digitação em manifesto. Prevenção: Helm/Kustomize com labels gerados, lint (`kubeconform`), smoke test pós-deploy.

### Perguntas de entrevista
1. Como o Service encontra os pods? (selector → Endpoints/EndpointSlices.)
2. Endpoints preenchidos mas "connection refused": o que verificar? (targetPort, a app escutando 0.0.0.0, NetworkPolicy.)
3. Diferença entre ClusterIP, NodePort, LoadBalancer?
4. Como testar um Service sem expor? (`kubectl port-forward svc/web 8080:80`, ou pod efêmero.)

---

<a id="vulnerable-image"></a>

## 16. Imagem Docker com vulnerabilidades

### Objetivo
Executar scan de imagem e de dependências com Trivy, ler severidades/CVEs e corrigir atualizando base e libs.

> O código e o Dockerfile em `security/samples/vulnerable-app/` são **inseguros de propósito**. Os resultados abaixo vêm do Trivy real (banco local), não são simulados.

### Contexto do incidente
O time de segurança reprova a imagem `lab-vuln:demo` no gate de release: "há CVEs CRITICAL".

### Como reproduzir
```bash
./lab.sh exercise vulnerable-image
```
Executado neste lab: **4 CRITICAL, 55 HIGH, 79 MEDIUM, 32 LOW** (+3 UNKNOWN) na imagem `python:3.8-slim-buster` + dependências antigas. (Os números mudam com o tempo conforme o banco de CVEs é atualizado.)

### Investigação
```bash
./lab.sh scan image lab-vuln:demo                                   # tabela completa
trivy image --skip-db-update --severity CRITICAL lab-vuln:demo      # só críticas
./lab.sh scan sample                                                # SCA do requirements.txt + secrets + Dockerfile (misconfig)
```
Exemplos de achados reais no `scan sample`: `pyyaml 5.3` — `CVE-2020-14343` (CRITICAL, corrigido em 5.4); `flask 0.12.2` — `CVE-2018-1000656` (HIGH, 0.12.3); `requests 2.19.1` — `CVE-2018-18074`; Dockerfile `DS-0031` (CRITICAL): segredo exposto em `ENV DB_PASSWORD`; `DS-0002`: roda como root.

**Como interpretar:** colunas *Library, Vulnerability, Severity, Installed, Fixed Version*. Se há *Fixed Version*, atualizar resolve. Sem correção disponível (`--ignore-unfixed` esconde) = aceitar risco/mitigar. Separe vulnerabilidades do **SO base** (trocar/atualizar imagem) das **dependências da app** (atualizar libs).

### Causa-raiz
Imagem base antiga (EOL) + dependências com CVEs conhecidos + segredo no Dockerfile + root.

### Como resolver
```bash
./lab.sh exercise vulnerable-image fix     # constrói lab-vuln:fixed (python:3.12-slim, libs atuais, USER não-root) e compara
```

### Como validar
```bash
./lab.sh exercise vulnerable-image validate    # 0 CRITICAL em lab-vuln:fixed
```
Resultado real neste lab: CRITICAL 4 → 0; HIGH 55 → 45 (restam pacotes do Debian sem correção disponível — é normal: gate por severidade + `--ignore-unfixed` + prazo para o resto).

### Limpeza
`./lab.sh exercise vulnerable-image reset`

### Modelo de RCA (resumo)
Causa: base e libs sem atualização. Prevenção: scan no CI (Trivy/Snyk Container), Renovate/Dependabot, imagens mínimas (slim/distroless), rebuild periódico.

### Perguntas de entrevista
1. SAST vs SCA vs container scan? 2. O que é CVSS e por que severidade ≠ risco real (exploitability, exposição)?
3. Como tratar uma CVE sem correção? 4. Por que não colocar segredo em `ENV`/camadas da imagem?

---

## Modelo de RCA reutilizável (Root Cause Analysis / Post-mortem)

Copie, preencha e arquive. Regras: **sem culpados** (blameless), fatos com horário, causa em sistema/processo, ações com dono e prazo.

```markdown
# RCA — <título curto> — <data>

**Severidade:** SEV1/2/3  **Duração:** hh:mm  **Autor:** <nome>  **Status:** rascunho/final

## 1. Resumo (2-3 linhas)
O que aconteceu, quem foi afetado e qual foi o impacto de negócio.

## 2. Impacto
- Usuários/serviços afetados:        - Métricas (erro %, latência, requisições perdidas):
- SLO/Error budget consumido:        - Impacto financeiro/contratual (se houver):

## 3. Linha do tempo (UTC-3)
| Hora  | Evento |
|-------|--------|
| hh:mm | Mudança/deploy X aplicada |
| hh:mm | Alerta Y disparou |
| hh:mm | Incidente declarado; <pessoa> assume como IC |
| hh:mm | Mitigação aplicada (ex.: rollback) |
| hh:mm | Serviço recuperado e validado |

## 4. Detecção
Como descobrimos? (alerta, cliente, ronda). Tempo até detectar (TTD): ___ . Poderíamos ter detectado antes?

## 5. Causa-raiz e fatores contribuintes
- Causa-raiz (use os "5 porquês"): ...
- Fatores contribuintes (falta de teste, alerta ausente, doc desatualizada...): ...
- O que **deu certo**: ...

## 6. Mitigação e resolução
O que foi feito, comandos relevantes, tempo até mitigar (TTM): ___ .

## 7. Validação da recuperação
Quais métricas/consultas comprovam que voltou ao normal?

## 8. Ações corretivas e preventivas
| Ação | Tipo (prevenir/detectar/mitigar) | Dono | Prazo | Ticket |
|------|------|------|------|------|

## 9. Lições aprendidas
...
```

**Os 5 porquês (exemplo — CrashLoopBackOff):** Por que o serviço caiu? O pod reiniciava. Por quê? Saía com código 3. Por quê? Faltava `DATABASE_URL`. Por quê? O manifesto novo não a incluía. Por quê? Não há validação de variáveis obrigatórias no CI. → ação: validar config no pipeline.

**Métricas de incidente:** TTD (detecção), TTA (reconhecimento), TTM (mitigação), TTR (resolução), MTTR médio.
