#!/usr/bin/env bash
# Funções compartilhadas pelo lab.sh e pelos exercícios. Não execute diretamente.
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$LAB_DIR/.data"          # estado local do lab (logs do Kind, tokens, repo do Jenkins, caches)
BIN_DIR="$LAB_DIR/bin"             # binários baixados pelo 'lab.sh install' (kind, kubectl, trivy)
export PATH="$BIN_DIR:$PATH"
CLUSTER="lab"
CTX="kind-lab"
LOGDIR="$DATA_DIR/kind-logs"
APP_IMAGE="lab-app:1.0.0"
export TRIVY_CACHE_DIR="$DATA_DIR/trivy-cache"

if [[ -t 1 ]]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'; else B=; G=; Y=; R=; C=; N=; fi
say()  { printf '%s▶ %s%s\n' "$B" "$*" "$N"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '%s✔ %s%s\n' "$G" "$*" "$N"; }
warn() { printf '%s⚠ %s%s\n' "$Y" "$*" "$N" >&2; }
err()  { printf '%s✘ %s%s\n' "$R" "$*" "$N" >&2; }
die()  { err "$*"; exit 1; }
# mostra o comando antes de executar (transparência: você aprende o comando real)
run()  { printf '  %s$ %s%s\n' "$C" "$*" "$N"; "$@"; }

kc() { kubectl --context "$CTX" "$@"; }

confirm() {   # confirm "pergunta"  (LAB_YES=1 pula a pergunta)
  [[ "${LAB_YES:-0}" == 1 ]] && return 0
  local a; read -r -p "$1 [s/N] " a; [[ "$a" =~ ^[sSyY]$ ]]
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' não encontrado. Rode: ./lab.sh install  (ou veja docs/01-INSTALLATION.md)"; }
mem_avail_mb() { awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo; }
port_in_use()  { ss -ltnH "( sport = :$1 )" 2>/dev/null | grep -q .; }
cluster_exists()  { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }
cluster_running() { [[ "$(docker inspect -f '{{.State.Running}}' "${CLUSTER}-control-plane" 2>/dev/null)" == true ]]; }
container_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]; }

# Avisa se a RAM disponível for menor que o necessário para o grupo.
mem_check() {  # mem_check <grupo> <MB necessários>
  local avail; avail="$(mem_avail_mb)"
  if (( avail < $2 )); then
    warn "RAM disponível: ${avail} MB; o grupo '$1' precisa de ~$2 MB. Feche navegador/VMs ou continue por sua conta."
    confirm "Continuar mesmo assim?" || die "Cancelado. Libere memória e tente de novo."
  fi
}
port_check() {  # port_check porta...
  local p busy=0
  for p in "$@"; do
    if port_in_use "$p"; then err "Porta $p já está em uso:"; ss -ltnp "( sport = :$p )" 2>/dev/null | tail -n +2 | sed 's/^/    /'; busy=1; fi
  done
  (( busy == 0 )) || die "Libere as portas acima (veja docs/10-LAB-TROUBLESHOOTING.md#portas-ocupadas)."
}

# ---------- helpers de exercícios ----------
inc_ns_create() { kc create namespace "$1" --dry-run=client -o yaml | kc apply -f - >/dev/null; kc label namespace "$1" lab-incident=true --overwrite >/dev/null; }
inc_ns_delete() {
  # só apaga namespaces criados pelo lab (label lab-incident=true) — nunca outros
  if kc get namespace "$1" -o jsonpath='{.metadata.labels.lab-incident}' 2>/dev/null | grep -q true; then
    info "removendo namespace $1 (e tudo dentro dele)"; kc delete namespace "$1" --wait=false >/dev/null
  else info "namespace $1 não existe (nada a remover)"; fi
}
# chama um endpoint HTTP DENTRO de um pod do app (a imagem slim não tem curl; usa python)
inc_call() {  # inc_call <ns> <deploy> <path>
  kc -n "$1" exec "deploy/$2" -- python -c "import urllib.request,sys;print(urllib.request.urlopen('http://localhost:8080$3',timeout=60).read().decode())"
}
need_cluster() { need kubectl; cluster_running || die "Cluster não está rodando. Rode: ./lab.sh start k8s"; }
