# DevOps Lab

Laboratório **local e gratuito** para estudar temas de DevOps/SRE/Cloud: Linux, Kubernetes/AKS, troubleshooting, CI/CD (Jenkins), Terraform, observabilidade (Golden Signals), segurança/qualidade (SonarQube, Trivy, Snyk) e conceitos AWS/Azure.

- Sem conta em nenhum serviço, sem cartão, sem nuvem. Tudo roda no seu computador (Docker + Kind).
- Internet só é usada na **instalação** (baixar binários, imagens, banco de CVEs, providers Terraform, pacotes pip). Depois os exercícios funcionam offline. Detalhes em [docs/01-INSTALLATION.md](docs/01-INSTALLATION.md).
- Nada sobe sozinho: você inicia **um grupo por vez** (a RAM é o recurso mais escasso).

## Arquitetura

```
 seu computador (Linux, Docker)
 ├─ Kind: cluster "lab"  (lab-control-plane + lab-worker)
 │    ├─ ns demo        → lab-app (2 pods, Service NodePort 30080, Ingress)
 │    ├─ ns monitoring  → Prometheus (descoberta de pods + cAdvisor)         http://127.0.0.1:9090
 │    ├─ ns ingress-nginx, kube-system (CoreDNS, metrics-server)
 │    └─ ns inc-*       → incidentes (criados/removidos pelos exercícios)
 ├─ grupo observability (Docker Compose): Grafana :3000 · Loki :3100 · Tempo :3200 · Alloy (coletor de logs)
 ├─ grupo cicd (Docker Compose): Jenkins :8088 → docker.sock + kubeconfig → faz build/deploy no Kind
 └─ grupo security (Docker Compose): SonarQube Community Build :9000     (+ Trivy local em ./bin)
```
Todos os containers do lab usam a rede Docker `kind`, então se enxergam por nome (`lab-loki`, `lab-sonarqube`, `lab-control-plane`).

## Ferramentas (todas gratuitas/open source)
Docker Engine + Compose · Kind · kubectl · Terraform · Jenkins LTS · Prometheus · Grafana · Loki · Tempo · OpenTelemetry (SDK no app) · Grafana Alloy · SonarQube Community Build · Trivy · Python/Flask (app demo).

## Pré-requisitos
KDE Neon (Ubuntu 24.04), 16 GB RAM, ~25 GB livres em disco, usuário no grupo `docker`. Verifique tudo com:
```bash
./lab.sh check
```

## Como iniciar
```bash
./lab.sh check                    # diagnóstico
./lab.sh install                  # baixa kind/kubectl/trivy em ./bin e o banco de CVEs (sem sudo)
./lab.sh install --apt            # opcional: htop, traceroute (pede sua senha sudo)
./lab.sh start k8s                # 1º: cluster + app demo + Prometheus (~3-5 min na 1ª vez)
./lab.sh start observability      # Grafana/Loki/Tempo (~1 min)
./lab.sh start cicd               # Jenkins (build da imagem ~3 min na 1ª vez)
./lab.sh start security           # SonarQube (~2-3 min) e depois ./lab.sh sonar-setup
```
**RAM aproximada por grupo:** k8s ~1,5 GB · observability ~0,7 GB · cicd ~1,2 GB · security ~2,5 GB. Para estudar Kubernetes + troubleshooting você só precisa de **k8s** (+ observability para Golden Signals). Se faltar RAM: `LAB_NODES=1 ./lab.sh start k8s` (cluster de 1 node) e suba security só quando for estudar Sonar.

Imagens:
<img width="1655" height="615" alt="image" src="https://github.com/user-attachments/assets/d8c0e297-e29b-44f1-a800-15941d38daa5" />
<img width="1660" height="187" alt="image" src="https://github.com/user-attachments/assets/71890005-949c-4773-b606-9aec7cd6a3c3" />
<img width="1311" height="307" alt="image" src="https://github.com/user-attachments/assets/c6c1d875-d854-410b-8872-00f07a87bd15" />
<img width="910" height="170" alt="image" src="https://github.com/user-attachments/assets/d49cd801-305b-4b50-a88e-4173afe5430c" />
<img width="1668" height="486" alt="image" src="https://github.com/user-attachments/assets/2c674348-f983-4025-b3a9-2a015ddb4769" />
<img width="713" height="84" alt="image" src="https://github.com/user-attachments/assets/6087d62e-f100-4166-b7d0-7bf2017c5442" />


## Como parar
```bash
./lab.sh stop observability       # ou: k8s | cicd | security | all   (não apaga nada)
./lab.sh status
./lab.sh reset                    # volta o namespace demo ao padrão e remove incidentes (pede confirmação)
./lab.sh cleanup                  # apaga cluster e containers (pede confirmação); --volumes também apaga dados
```

## Como verificar se está tudo funcionando
```bash
./lab.sh status
curl -s http://127.0.0.1:30080/info                        # app
curl -s http://127.0.0.1:9090/-/ready                      # Prometheus
curl -s http://127.0.0.1:3000/api/health                   # Grafana
./lab.sh urls                                              # todos os endereços e credenciais locais
```

## Sequência recomendada de estudo (um dia)
| Hora | Tema | Documento | Exercícios |
|---|---|---|---|
| 1h | Linux e redes | [02](docs/02-LINUX-AND-NETWORKING.md) | `linux-cpu`, `linux-disk`, `linux-port`, `linux-dns` |
| 1h30 | Kubernetes/kubectl | [03](docs/03-KUBERNETES.md) | leia + rode os comandos no ns `demo` |
| 1h30 | Troubleshooting de pods | [08](docs/08-INCIDENTS-RCA.md) | `kubernetes-crashloop`, `oomkilled`, `imagepull-backoff`, `pending-pod`, `service-no-endpoints`, `dns-failure`, `rollback` |
| 1h | Jenkins/CI-CD | [05](docs/05-JENKINS-CICD.md) | `pipeline run`, `jenkins-pipeline-fail` |
| 45min | Terraform | [04](docs/04-TERRAFORM.md) | `./lab.sh tf 01 ...` e `tf 02 ...` |
| 1h | Observabilidade e Golden Signals | [06](docs/06-OBSERVABILITY-DATADOG.md) | `http-500`, `high-latency`, `high-cpu` |
| 45min | SonarQube/Trivy/Snyk | [07](docs/07-SECURITY-QUALITY.md) | `vulnerable-image`, `scan sonar-sample` |
| 30min | AWS e Azure | [09](docs/09-CLOUD-AWS-AZURE.md) | leitura (tabelas comparativas) |

## Organização dos diretórios
```
lab.sh                  script principal (./lab.sh help)
app/                    app Flask demo, testes, Dockerfile, Jenkinsfile, sonar-project.properties
k8s/base/               manifests do app (namespace, config, deployment, service, ingress)
k8s/addons/             Prometheus, metrics-server e ingress-nginx (versões fixas)
kind/                   configuração do cluster Kind
observability/          compose + configs de Grafana (dashboard Golden Signals), Loki, Tempo, Alloy
cicd/                   Jenkins (Dockerfile, plugins, Configuration as Code) + compose
security/               compose do SonarQube + samples/vulnerable-app (inseguro de propósito)
terraform/              01-local-basics (sem cluster) e 02-kubernetes (no Kind)
exercises/<nome>/       run.sh (reproduce|fix|validate|reset) + exercise.md (roteiro completo)
scripts/                lib.sh e gerador do doc 08
docs/                   documentação 01 a 10
bin/ e .data/           binários e estado local (ignorados pelo Git)
```

## Limitações conhecidas (honestas)
- **Datadog / SonarCloud / Snyk** exigem conta: não são executados. Equivalentes locais: Grafana+Prometheus+Loki+Tempo, SonarQube e Trivy. As diferenças estão em [06](docs/06-OBSERVABILITY-DATADOG.md) e [07](docs/07-SECURITY-QUALITY.md).
- **AKS/EKS/AWS/Azure** não são provisionados; [09](docs/09-CLOUD-AWS-AZURE.md) e a seção Kind×AKS do [03](docs/03-KUBERNETES.md) fazem a ponte conceitual.
- Instalação e o **primeiro** `build` precisam de internet (Docker Hub, PyPI, GitHub, registry.terraform.io, banco do Trivy). Depois ficam em cache.
- Alertas são avaliados pelo Prometheus (sem Alertmanager, para poupar RAM): veja em http://127.0.0.1:9090/alerts.
- Jenkins monta o `docker.sock` do host (equivale a root): aceitável só neste lab local.
- O Jenkins usa um repositório git local (`.data/app-repo`) em vez de GitHub, para não depender de conta/rede.
- Pode ser necessário `sudo` apenas para instalar `htop`/`traceroute` (opcional).
- Ingress-NGINX foi aposentado pelo projeto Kubernetes em 2026 (sem novas versões); continua funcional para estudo e o conceito (Ingress + controller) é o mesmo.

Problemas? [docs/10-LAB-TROUBLESHOOTING.md](docs/10-LAB-TROUBLESHOOTING.md).
