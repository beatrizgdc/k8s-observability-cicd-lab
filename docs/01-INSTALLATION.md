# 01 — Instalação e dependências (KDE Neon / Ubuntu 24.04 "noble")

> Estado verificado nesta máquina durante a construção do lab: Docker 29.1.3 ✔, Docker Compose 2.40.3 ✔, Terraform 1.17.0 ✔, git ✔, curl ✔, jq ✔, python3 3.12 ✔, dig/nslookup/nc/ss/netstat/ip/mtr ✔. Instalados pelo lab em `./bin`: kind v0.33.0, kubectl v1.37.2, trivy 0.76.1, sonar-scanner 8.3 (opcional). **Pendentes (opcionais, precisam de sudo):** `htop`, `traceroute`.

## 1. Verificar o que já está instalado
```bash
./lab.sh check          # resumo colorido: ✔ presente / ✘ ausente, RAM, portas
```
Manualmente:
```bash
cat /etc/os-release | head -3
docker --version && docker compose version
kind version; kubectl version --client; terraform version
trivy --version; jq --version; git --version; python3 --version
free -h; df -h .; nproc
```
Esperado: cada comando imprime uma versão. `command not found` = ausente (veja a seção da ferramenta).

## 2. Instalação automática (sem sudo)
```bash
./lab.sh install          # kind, kubectl, trivy -> ./bin ; banco de CVEs do Trivy -> .data/trivy-cache
./lab.sh install sonar-scanner   # opcional (SAST do sample no host)
./lab.sh install images   # opcional: pré-baixa imagens base (~1 GB)
./lab.sh install --apt    # htop, traceroute, dnsutils, netcat-openbsd via apt (usa sudo; pede sua senha)
```
O `lab.sh` coloca `./bin` no PATH **apenas durante a execução dele**. Para usar `kubectl`/`kind`/`trivy` direto no seu terminal:
```bash
export PATH="$PWD/bin:$PATH"       # na pasta do lab
```

## 3. Instalação manual por ferramenta

### Docker Engine + Compose (obrigatório)
Opção simples (repositório Ubuntu):
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod -aG docker $USER      # depois: faça logout/login (ou: newgrp docker)
```
Validar: `docker run --rm hello-world` e `docker compose version`.
Alternativa oficial (versões mais novas): https://docs.docker.com/engine/install/ubuntu/ (KDE Neon = Ubuntu noble).

### kubectl
```bash
curl -fsSLo bin/kubectl https://dl.k8s.io/release/v1.37.2/bin/linux/amd64/kubectl && chmod +x bin/kubectl
```
Validar: `bin/kubectl version --client`.

### Kind
```bash
curl -fsSLo bin/kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64 && chmod +x bin/kind
```
Validar: `bin/kind version`.

### Terraform
```bash
sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform
```
(KDE Neon: se `lsb_release -cs` não retornar `noble`, troque por `noble`.) Alternativa gratuita equivalente: OpenTofu. Validar: `terraform version`.

### Trivy
`./lab.sh install` (binário em `bin/trivy`). Alternativa apt: https://trivy.dev/latest/getting-started/installation/.

### Utilitários de Linux/redes
```bash
sudo apt-get install -y htop traceroute dnsutils netcat-openbsd net-tools iproute2 iputils-ping jq curl wget
```
Validar: `htop --version`, `traceroute -V`, `dig -v`, `nc -h 2>&1 | head -1`.

### Python 3 / pip
Já vem no Ubuntu (`python3 --version`). Só é necessário no host se você for rodar `pytest` fora do container: `python3 -m venv .venv && .venv/bin/pip install -r app/requirements-dev.txt`.

## 4. Validar o ambiente completo
```bash
docker run --rm hello-world | head -3
./lab.sh check
./lab.sh start k8s && kubectl --context kind-lab get nodes      # 2 nodes Ready
```

## 5. Problemas comuns
| Erro | Causa | Solução |
|---|---|---|
| `permission denied while trying to connect to the Docker daemon socket` | usuário sem grupo docker ou sessão antiga | `sudo usermod -aG docker $USER`; logout/login; `groups` deve listar `docker` |
| `Cannot connect to the Docker daemon` | serviço parado | `sudo systemctl start docker` ; `systemctl status docker` |
| `E: Unable to locate package docker-compose-v2` | apt desatualizado / repositório | `sudo apt-get update`; ou instale o plugin oficial (Docker repo) |
| `dpkg lock` (`Could not get lock /var/lib/dpkg/lock-frontend`) | outro apt/Discover em execução | aguarde; `ps aux | grep -E 'apt|dpkg'`; não apague locks à força |
| `GPG error ... NO_PUBKEY` | chave do repositório ausente | repita o passo do `gpg --dearmor` da ferramenta |
| `kind: command not found` após instalar | `./bin` fora do PATH | `export PATH="$PWD/bin:$PATH"` ou use `./lab.sh` |
| Kind: `too many open files` / `failed to create inotify` | limites inotify | `sudo sysctl fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512` |
| Disco cheio ao baixar imagens | `/var/lib/docker` | `docker system df` ; remova **o que for seu e não usa** (`docker image prune` pede confirmação) |
| `sudo: a password is required` em scripts | sudo precisa de senha | rode o comando `sudo apt-get install ...` você mesmo no terminal |

Mais casos do próprio lab: [10-LAB-TROUBLESHOOTING.md](10-LAB-TROUBLESHOOTING.md).
