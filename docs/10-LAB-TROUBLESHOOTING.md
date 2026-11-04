# 10 — Problemas do próprio laboratório

Comece sempre por `./lab.sh check` e `./lab.sh status`.

## Instalação
| Sintoma | Causa provável | Solução |
|---|---|---|
| `permission denied ... /var/run/docker.sock` | usuário fora do grupo docker | `sudo usermod -aG docker $USER` e **faça logout/login** (ou `newgrp docker`) |
| `docker: command not found` | Docker ausente | veja [01-INSTALLATION.md](01-INSTALLATION.md) |
| `./lab.sh install` falha no `curl` | sem internet/proxy | teste `curl -I https://github.com`; defina `https_proxy` se necessário |
| trivy: `--skip-db-update` sem banco | DB não baixado | `./lab.sh install` (baixa `.data/trivy-cache`) |
| `terraform init` não baixa providers | sem acesso a registry.terraform.io no 1º init | conecte-se à internet 1 vez; depois usa `.data/tf-plugin-cache` |

## Portas ocupadas {#portas-ocupadas}
O lab usa: 8080, 8443, 30080, 9090 (k8s) · 3000, 3100, 3200 (observability) · 8088 (Jenkins) · 9000 (Sonar).
```bash
ss -ltnp 'sport = :9090'     # quem está usando?
```
Pare o processo ou container que a ocupa. Para mudar a porta do host, edite o `ports:` do compose correspondente ou `hostPort` em `kind/kind-config.yaml` (exige recriar o cluster).

## Falta de memória
- Sintomas: containers `Exited (137)`, `OOMKilled`, sistema lento, swap cheio (`free -h`).
- Veja o consumo: `docker stats --no-stream` e `kubectl top nodes`.
- Ações: `./lab.sh stop security` (o maior) · `./lab.sh stop cicd` · `LAB_NODES=1 ./lab.sh start k8s` (1 node; recrie com `cleanup`) · feche navegador/VMs.
- O `start` avisa quando a RAM livre é menor que a necessária e pergunta se deve continuar.

## Containers que não iniciam
```bash
docker ps -a --filter name=lab-
docker logs --tail 50 lab-loki        # (ou lab-grafana, lab-jenkins, lab-sonarqube, lab-tempo, lab-alloy)
```
| Container | Sintoma | Solução |
|---|---|---|
| lab-sonarqube | `max virtual memory areas vm.max_map_count too low` | o lab já desativa mmap; se ainda ocorrer: `sudo sysctl -w vm.max_map_count=262144` |
| lab-jenkins | `permission denied` no volume | volume `lab-cicd_jenkins-home` criado por outro uid: `docker volume rm lab-cicd_jenkins-home` (perde jobs/histórico) |
| lab-loki | "ingester not ready" logo após subir | normal por ~20 s |
| lab-alloy | `404` ao enviar ao Loki | URL do `loki.write` deve ser `/loki/api/v1/push` (já está) |
| kind create | `failed to create cluster` / timeout | `docker system df`; `./lab.sh cleanup` e `./lab.sh start k8s`; verifique inotify: `sysctl fs.inotify.max_user_instances` (≥ 512 ajuda: `sudo sysctl fs.inotify.max_user_instances=512`) |

## Erros de configuração comuns
- `Error: required variable LAB_KIND_LOGDIR` → você rodou `docker compose` à mão; use `./lab.sh start observability`.
- `kind load` / `ctr: content digest not found` → bug conhecido com imagens multi-arch no Docker ≥25; o lab usa `docker save --platform` (já tratado).
- Ingress `connection refused` em `lab.localtest.me:8080` → o controller pode estar subindo: `kubectl -n ingress-nginx get pods`. `localtest.me` precisa de DNS; alternativa: `curl -H 'Host: lab.localtest.me' http://127.0.0.1:8080/`.
- `kubectl` aponta para outro cluster → `kubectl config use-context kind-lab` (o lab usa `--context kind-lab` nos exercícios).
- Pipeline Jenkins: `Checkout ... local directory` → já habilitado por `ALLOW_LOCAL_CHECKOUT`; se mudou o Dockerfile do Jenkins, `./lab.sh start cicd` reconstrói.
- Pipeline falha no Security Scan por falta de DB → `./lab.sh install`.
- Sonar stage "SonarQube indisponível" → `./lab.sh start security && ./lab.sh sonar-setup`.
- `.data/kind-logs` não pode ser apagado (arquivos de root) → `./lab.sh cleanup` limpa via container.

## Recomeçar do zero
```bash
./lab.sh cleanup            # cluster + containers (volumes preservados)
./lab.sh cleanup --volumes  # também Jenkins/Sonar/Grafana/Loki/Tempo (pede confirmação)
rm -rf .data                # (manual) repo do Jenkins, tokens, caches
```
Imagens e containers que **não** são do lab nunca são tocados.
