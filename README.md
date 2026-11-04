<div align="center">

# 🧪 DevOps Lab

**Laboratório local e gratuito de DevOps / SRE / Cloud**
Kubernetes · Observabilidade · CI/CD · Terraform · Segurança

![Kubernetes](https://img.shields.io/badge/Kubernetes-Kind-326CE5?logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-CI%2FCD-D24939?logo=jenkins&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-metrics-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-dashboards-F46800?logo=grafana&logoColor=white)
![SonarQube](https://img.shields.io/badge/SonarQube-quality-4E9BCD?logo=sonarqube&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)
![Custo](https://img.shields.io/badge/custo-%240-success)

</div>

> Sem conta em nenhum serviço, sem cartão, sem nuvem. Tudo roda no seu computador (Docker + Kind).

## 📑 Índice

- [Visão geral](#-visão-geral)
- [Arquitetura](#-arquitetura)
- [Pré-requisitos](#-pré-requisitos)
- [Como iniciar](#-como-iniciar)
- [Como verificar](#-como-verificar-se-está-tudo-funcionando)
- [Como parar](#-como-parar)
- [Roteiro de estudo](#-roteiro-de-estudo-um-dia)
- [Estrutura de diretórios](#-estrutura-de-diretórios)
- [Limitações conhecidas](#-limitações-conhecidas)

## 🎯 Visão geral

| | |
|---|---|
| **Temas** | Linux, Kubernetes/AKS, troubleshooting, CI/CD (Jenkins), Terraform, observabilidade (Golden Signals), segurança/qualidade (SonarQube, Trivy, Snyk) e conceitos AWS/Azure |
| **Exercícios** | 16 cenários de incidente isolados e reversíveis (`./lab.sh exercise list`) |
| **Internet** | Só na **instalação** (binários, imagens, banco de CVEs, providers Terraform, pacotes pip). Depois tudo funciona offline. Veja [docs/01-INSTALLATION.md](docs/01-INSTALLATION.md) |
| **Recursos** | Nada sobe sozinho: você inicia **um grupo por vez**, porque a RAM é o recurso mais escasso |

**Ferramentas (todas open source):** Docker Engine + Compose · Kind · kubectl · Terraform · Jenkins LTS · Prometheus · Grafana · Loki · Tempo · OpenTelemetry · Grafana Alloy · SonarQube Community Build · Trivy · Python/Flask (app demo).

## 🏗️ Arquitetura

```mermaid
flowchart TB
    subgraph host["💻 Seu computador (Linux + Docker) · rede Docker 'kind'"]
        subgraph kind["☸️ Kind: cluster lab"]
            app["ns demo<br/>lab-app · 2 pods · NodePort 30080 · Ingress"]
            mon["ns monitoring<br/>Prometheus :9090"]
            sys["ns ingress-nginx · kube-system<br/>CoreDNS · metrics-server"]
            inc["ns inc-*<br/>incidentes dos exercícios"]
        end
        subgraph obs["📈 grupo observability"]
            graf["Grafana :3000"]
            loki["Loki :3100"]
            tempo["Tempo :3200"]
            alloy["Alloy"]
        end
        subgraph cicd["🔁 grupo cicd"]
            jen["Jenkins :8088"]
        end
        subgraph sec["🔒 grupo security"]
            sonar["SonarQube :9000"]
            trivy["Trivy (./bin)"]
        end
    end

    mon -->|métricas| graf
    alloy -->|logs dos pods| loki
    app -->|traces OTLP| tempo
    loki --> graf
    tempo --> graf
    jen -->|build + deploy| app
    jen -->|análise| sonar
    jen -->|scan de imagem| trivy
```

Todos os containers usam a rede Docker `kind`, então se enxergam por nome (`lab-loki`, `lab-sonarqube`, `lab-control-plane`).

| Grupo | Serviços | Portas | RAM aprox. |
|---|---|---|---|
| `k8s` | Kind, app demo, Prometheus, ingress | 8080/8443 · 30080 · 9090 | ~1,5 GB |
| `observability` | Grafana, Loki, Tempo, Alloy | 3000 · 3100 · 3200 | ~0,7 GB |
| `cicd` | Jenkins | 8088 | ~1,2 GB |
| `security` | SonarQube (+ Trivy local) | 9000 | ~2,5 GB |

## ✅ Pré-requisitos

KDE Neon (Ubuntu 24.04), 16 GB RAM, ~25 GB livres em disco e usuário no grupo `docker`. Verifique tudo com:

```bash
./lab.sh check
```

## 🚀 Como iniciar

```bash
./lab.sh check                    # diagnóstico
./lab.sh install                  # baixa kind/kubectl/trivy em ./bin e o banco de CVEs (sem sudo)
./lab.sh install --apt            # opcional: htop, traceroute (pede sua senha sudo)
./lab.sh start k8s                # 1º: cluster + app demo + Prometheus (~3-5 min na 1ª vez)
./lab.sh start observability      # Grafana/Loki/Tempo (~1 min)
./lab.sh start cicd               # Jenkins (build da imagem ~3 min na 1ª vez)
./lab.sh start security           # SonarQube (~2-3 min) e depois ./lab.sh sonar-setup
```

> 💡 Para estudar Kubernetes e troubleshooting basta o grupo **k8s** (+ **observability** para Golden Signals).
> Se faltar RAM: `LAB_NODES=1 ./lab.sh start k8s` (cluster de 1 node) e suba `security` só quando for estudar Sonar.

<details>
<summary>📸 <b>Capturas: subindo o lab</b></summary>
<br>

<img width="820" alt="Subindo o lab, etapa 1" src="https://github.com/user-attachments/assets/d8c0e297-e29b-44f1-a800-15941d38daa5" />

<img width="820" alt="Subindo o lab, etapa 2" src="https://github.com/user-attachments/assets/71890005-949c-4773-b606-9aec7cd6a3c3" />

<img width="820" alt="Subindo o lab, etapa 3" src="https://github.com/user-attachments/assets/c6c1d875-d854-410b-8872-00f07a87bd15" />

<img width="820" alt="Subindo o lab, etapa 4" src="https://github.com/user-attachments/assets/d49cd801-305b-4b50-a88e-4173afe5430c" />

<img width="820" alt="Subindo o lab, etapa 5" src="https://github.com/user-attachments/assets/2c674348-f983-4025-b3a9-2a015ddb4769" />

<img width="820" alt="Subindo o lab, etapa 6" src="https://github.com/user-attachments/assets/6087d62e-f100-4166-b7d0-7bf2017c5442" />

</details>

## 🔍 Como verificar se está tudo funcionando

```bash
./lab.sh status
curl -s http://127.0.0.1:30080/info                        # app
curl -s http://127.0.0.1:9090/-/ready                      # Prometheus
curl -s http://127.0.0.1:3000/api/health                   # Grafana
./lab.sh urls                                              # todos os endereços e credenciais locais
```

<details>
<summary>📸 <b>Capturas: verificação</b></summary>
<br>

<img width="700" alt="Verificação, etapa 1" src="https://github.com/user-attachments/assets/cc34fbd5-1a63-4f7d-ac8c-4e183643201b" />

<img width="820" alt="Verificação, etapa 2" src="https://github.com/user-attachments/assets/6a1dbbe1-40cb-4c7d-9534-4464d16aaed0" />

<img width="820" alt="Verificação, etapa 3" src="https://github.com/user-attachments/assets/d70d9dcb-167c-4fbf-bcc2-3086b88db9f0" />

</details>

## 🛑 Como parar

```bash
./lab.sh stop observability       # ou: k8s | cicd | security | all   (não apaga nada)
./lab.sh status
./lab.sh reset                    # volta o namespace demo ao padrão e remove incidentes (pede confirmação)
./lab.sh cleanup                  # apaga cluster e containers (pede confirmação); --volumes também apaga dados
```

<details>
<summary>📸 <b>Capturas: parando e limpando</b></summary>
<br>

<img width="635" alt="Parando o lab, etapa 1" src="https://github.com/user-attachments/assets/06a00333-2cab-41ed-ad95-221f14a4c771" />

<img width="635" alt="Parando o lab, etapa 2" src="https://github.com/user-attachments/assets/b874c662-1c54-49ce-8a69-f82ff6e8b59f" />

<img width="691" alt="Parando o lab, etapa 3" src="https://github.com/user-attachments/assets/ef6cd331-d1fc-43ae-8b10-7953eb2b5d8b" />

</details>

## 📚 Roteiro de estudo (um dia)

| Hora | Tema | Documento | Exercícios |
|---|---|---|---|
| 1h | 🐧 Linux e redes | [02](docs/02-LINUX-AND-NETWORKING.md) | `linux-cpu`, `linux-disk`, `linux-port`, `linux-dns` |
| 1h30 | ☸️ Kubernetes/kubectl | [03](docs/03-KUBERNETES.md) | leia + rode os comandos no ns `demo` |
| 1h30 | 🩺 Troubleshooting de pods | [08](docs/08-INCIDENTS-RCA.md) | `kubernetes-crashloop`, `oomkilled`, `imagepull-backoff`, `pending-pod`, `service-no-endpoints`, `dns-failure`, `rollback` |
| 1h | 🔁 Jenkins / CI-CD | [05](docs/05-JENKINS-CICD.md) | `pipeline run`, `jenkins-pipeline-fail` |
| 45min | 🏗️ Terraform | [04](docs/04-TERRAFORM.md) | `./lab.sh tf 01 ...` e `tf 02 ...` |
| 1h | 📈 Observabilidade e Golden Signals | [06](docs/06-OBSERVABILITY-DATADOG.md) | `http-500`, `high-latency`, `high-cpu` |
| 45min | 🔒 SonarQube / Trivy / Snyk | [07](docs/07-SECURITY-QUALITY.md) | `vulnerable-image`, `scan sonar-sample` |
| 30min | ☁️ AWS e Azure | [09](docs/09-CLOUD-AWS-AZURE.md) | leitura (tabelas comparativas) |

## 🗂️ Estrutura de diretórios

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

## ⚠️ Limitações conhecidas

- **Datadog / SonarCloud / Snyk** exigem conta: não são executados. Equivalentes locais: Grafana + Prometheus + Loki + Tempo, SonarQube e Trivy. As diferenças estão em [06](docs/06-OBSERVABILITY-DATADOG.md) e [07](docs/07-SECURITY-QUALITY.md).
- **AKS/EKS/AWS/Azure** não são provisionados; [09](docs/09-CLOUD-AWS-AZURE.md) e a seção Kind×AKS do [03](docs/03-KUBERNETES.md) fazem a ponte conceitual.
- Instalação e o **primeiro** `build` precisam de internet (Docker Hub, PyPI, GitHub, registry.terraform.io, banco do Trivy). Depois ficam em cache.
- Alertas são avaliados pelo Prometheus (sem Alertmanager, para poupar RAM): veja em http://127.0.0.1:9090/alerts.
- Jenkins monta o `docker.sock` do host (equivale a root): aceitável só neste lab local.
- O Jenkins usa um repositório git local (`.data/app-repo`) em vez de GitHub, para não depender de conta/rede.
- Pode ser necessário `sudo` apenas para instalar `htop`/`traceroute` (opcional).
- Ingress-NGINX foi aposentado pelo projeto Kubernetes em 2026 (sem novas versões); continua funcional para estudo e o conceito (Ingress + controller) é o mesmo.

---

Problemas? Veja [docs/10-LAB-TROUBLESHOOTING.md](docs/10-LAB-TROUBLESHOOTING.md).
