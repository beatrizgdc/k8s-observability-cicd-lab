#!/usr/bin/env bash
# DevOps Lab — script principal. Uso: ./lab.sh help
# Princípios: mostra cada comando real que executa; nunca apaga dados sem pedir confirmação.
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"
cd "$LAB_DIR"
trap 'err "falhou na linha $LINENO: $BASH_COMMAND"' ERR

KIND_VERSION=v0.33.0; KUBECTL_VERSION=v1.37.2; TRIVY_VERSION=0.76.1
SONAR_PASS='Lab-Admin-2026!'      # senha local do SonarQube do lab (nunca use em outro lugar)

usage() { cat <<EOT
${B}DevOps Lab${N}

  ./lab.sh check                      verifica dependências, RAM, disco e portas
  ./lab.sh install [--apt] [images]   baixa kind/kubectl/trivy em ./bin (sem sudo); --apt instala htop/traceroute (sudo)
  ./lab.sh start  <k8s|observability|cicd|security>   inicia UM grupo (nada sobe sozinho)
  ./lab.sh stop   [grupo|all]         para sem apagar nada (dados/volumes preservados)
  ./lab.sh status                     estado de cada grupo, URLs e memória
  ./lab.sh reset                      volta o namespace 'demo' ao estado inicial e remove cenários inc-* (pede confirmação)
  ./lab.sh cleanup [--volumes]        remove cluster e containers do lab (pede confirmação; volumes só com --volumes)

  ./lab.sh exercise list              lista os exercícios
  ./lab.sh exercise <nome> [reproduce|fix|validate|reset|guide]   (padrão: reproduce)
  ./lab.sh traffic [segundos] [req/s] gera tráfego no app (para dashboards)
  ./lab.sh pipeline run [PARAM=valor] executa a pipeline Jenkins e mostra o log
  ./lab.sh sonar-setup                configura o SonarQube local (troca senha, gera token)
  ./lab.sh scan <fs|image|sample> [alvo]   Trivy (SCA, imagem) usando o banco local
  ./lab.sh tf <01|02> <comando...>    Terraform dos exercícios (ex.: ./lab.sh tf 01 init)
  ./lab.sh urls                       endereços e credenciais locais
EOT
}

# ------------------------------------------------------------------ check
cmd_check() {
  say "Sistema"
  info "SO: $(. /etc/os-release; echo "$PRETTY_NAME") | kernel $(uname -r)"
  info "CPU: $(lscpu | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2}') ($(nproc) threads)"
  info "RAM total/disponível: $(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo) MB / $(mem_avail_mb) MB"
  info "Disco livre em $LAB_DIR: $(df -h --output=avail "$LAB_DIR" | tail -1 | tr -d ' ')"
  (( $(mem_avail_mb) < 2500 )) && warn "Pouca RAM livre. Inicie um grupo por vez e feche apps pesados (navegador, VMs)."
  say "Ferramentas obrigatórias"
  local miss=0 t v
  for t in docker kind kubectl terraform curl jq git python3; do
    if command -v "$t" >/dev/null; then
      case $t in
        docker) v="$(docker --version)";; kind) v="$(kind version)";; kubectl) v="$(kubectl version --client 2>/dev/null | head -1)";;
        terraform) v="$(terraform version | head -1)";; *) v="$($t --version 2>&1 | head -1)";;
      esac; ok "$t: $v"
    else err "$t AUSENTE"; miss=1; fi
  done
  docker compose version >/dev/null 2>&1 && ok "docker compose: $(docker compose version --short)" || { err "docker compose AUSENTE"; miss=1; }
  docker info >/dev/null 2>&1 && ok "daemon Docker acessível sem sudo" || { err "sem acesso ao Docker (grupo 'docker'? daemon ativo?)"; miss=1; }
  say "Ferramentas opcionais (exercícios Linux/segurança)"
  for t in trivy htop traceroute dig nslookup nc ss netstat ip mtr; do
    command -v "$t" >/dev/null && ok "$t" || warn "$t ausente $( [[ $t == trivy ]] && echo '(./lab.sh install)' || echo '(./lab.sh install --apt)')"
  done
  say "Portas usadas pelo lab"
  for p in 8080 8443 30080 9090 3000 3100 3200 8088 9000; do port_in_use "$p" && warn "porta $p ocupada" || ok "porta $p livre"; done
  (( miss == 0 )) && ok "Dependências obrigatórias OK" || { err "Faltam dependências obrigatórias: ./lab.sh install"; return 1; }
}

# ------------------------------------------------------------------ install
dl() { say "baixando $1"; curl -fsSL -o "$2" "$3"; chmod +x "$2"; }
cmd_install() {
  mkdir -p "$BIN_DIR" "$DATA_DIR"
  command -v docker >/dev/null || die "Docker ausente. Siga docs/01-INSTALLATION.md (seção Docker)."
  command -v terraform >/dev/null || warn "Terraform ausente: veja docs/01-INSTALLATION.md (seção Terraform)."
  command -v kind >/dev/null    || dl kind    "$BIN_DIR/kind"    "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64"
  command -v kubectl >/dev/null || dl kubectl "$BIN_DIR/kubectl" "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
  if ! command -v trivy >/dev/null; then
    say "baixando trivy"; local t; t="$(mktemp -d)"
    curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" | tar -xz -C "$t" trivy
    mv "$t/trivy" "$BIN_DIR/trivy"; rmdir "$t"
  fi
  ok "ferramentas em $BIN_DIR"
  mkdir -p "$TRIVY_CACHE_DIR"
  if [[ ! -f "$TRIVY_CACHE_DIR/db/trivy.db" ]]; then
    say "baixando banco de vulnerabilidades do Trivy (precisa de internet SÓ nesta etapa; depois funciona offline)"
    trivy image --download-db-only || warn "falha ao baixar o banco do Trivy; os scans não funcionarão offline até conseguir"
  fi
  for a in "$@"; do
    case $a in
      --apt)
        local pk=() ; command -v htop >/dev/null || pk+=(htop); command -v traceroute >/dev/null || pk+=(traceroute)
        command -v dig >/dev/null || pk+=(dnsutils); command -v nc >/dev/null || pk+=(netcat-openbsd)
        if ((${#pk[@]})); then run sudo apt-get install -y "${pk[@]}"; else ok "pacotes apt já presentes"; fi;;
      sonar-scanner)
        local v=8.3.1.16491 z; z="$(mktemp -d)"; say "baixando sonar-scanner $v (~60 MB, inclui JRE)"
        curl -fsSL -o "$z/s.zip" "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-$v-linux-x64.zip"
        unzip -q "$z/s.zip" -d "$BIN_DIR" && ln -sf "$BIN_DIR/sonar-scanner-$v-linux-x64/bin/sonar-scanner" "$BIN_DIR/sonar-scanner"; rm -rf "$z"; ok "sonar-scanner em bin/";;
      images)
        say "pré-baixando imagens base (~1 GB)"
        for i in python:3.12-slim busybox:1.37 nginx:1.27-alpine python:3.8-slim-buster; do run docker pull -q "$i"; done;;
    esac
  done
  ok "install concluído. Próximo: ./lab.sh start k8s"
}

# ------------------------------------------------------------------ k8s
render_kind_config() {
  local out="$DATA_DIR/kind-config.yaml" worker="" line
  [[ "${LAB_NODES:-2}" == 2 ]] && worker="$(<kind/worker-snippet.yaml)"
  : > "$out"
  while IFS= read -r line; do
    if [[ "$line" == "#__WORKER__" ]]; then [[ -n "$worker" ]] && printf '%s\n' "${worker//__LOGDIR__/$LOGDIR}" >> "$out"
    else printf '%s\n' "${line//__LOGDIR__/$LOGDIR}" >> "$out"; fi
  done < kind/kind-config.yaml
}
load_image() {  # garante a imagem no docker local e no Kind
  # 'docker save --platform' evita o erro "content digest not found" de imagens multi-arch com Docker 25+
  docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null
  local tar="$DATA_DIR/img-load.tar"
  docker save --platform linux/amd64 "$1" -o "$tar" 2>/dev/null && kind load image-archive "$tar" --name "$CLUSTER" >/dev/null 2>&1 \
    || warn "não consegui pré-carregar $1 (o node tentará baixar da internet)"
  rm -f "$tar"
}
build_app() {  # build_app <tag> [versão]
  run docker build -q -t "$1" --build-arg "APP_VERSION=${2:-${1#*:}}" app/ >/dev/null
  kind load docker-image "$1" --name "$CLUSTER" >/dev/null
}
start_k8s() {
  need docker; need kind; need kubectl
  mem_check k8s 1500; mkdir -p "$LOGDIR/control-plane" "$LOGDIR/worker"   # uma pasta por node: o kubelet apaga logs "órfãos" da pasta que usa
  if cluster_exists; then
    if cluster_running; then ok "cluster '$CLUSTER' já está rodando"; else
      say "religando nodes existentes"; run docker start "${CLUSTER}-control-plane" $(docker ps -a --format '{{.Names}}' | grep -x "${CLUSTER}-worker" || true) >/dev/null
      sleep 8; kc wait --for=condition=Ready nodes --all --timeout=120s
    fi
  else
    port_check 8080 8443 30080 9090
    render_kind_config
    say "criando cluster Kind (primeira vez baixa a imagem do node, ~1 GB)"
    run kind create cluster --config "$DATA_DIR/kind-config.yaml" --wait 180s
    if [[ "${LAB_NODES:-2}" == 1 ]]; then run kc taint nodes "${CLUSTER}-control-plane" node-role.kubernetes.io/control-plane- ; fi
  fi
  say "carregando imagens no cluster"
  build_app "$APP_IMAGE" 1.0.0
  for i in $(grep -hv '^#' scripts/images.txt) ; do load_image "$i"; done
  for i in $(grep -h 'image:' k8s/addons/*.yaml | awk '{print $2}' | sed 's/@sha256.*//' | sort -u); do load_image "$i"; done
  say "instalando addons: metrics-server, ingress-nginx, Prometheus"
  kc apply -f k8s/addons/metrics-server.yaml >/dev/null
  kc -n kube-system patch deploy metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null 2>&1 || true
  kc apply -f k8s/addons/ingress-nginx.yaml >/dev/null
  kc apply -f k8s/addons/monitoring.yaml >/dev/null
  say "aguardando o ingress (o webhook de admissão precisa estar no ar antes de criar Ingress)"
  kc -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=240s || warn "ingress não ficou pronto (opcional)"
  say "aplicando a aplicação demo (namespace demo)"
  for _ in 1 2 3 4 5; do kc apply -f k8s/base/ >/dev/null 2>&1 && break; sleep 5; done
  kc apply -f k8s/base/ >/dev/null
  kc -n demo rollout status deploy/lab-app --timeout=180s
  kc -n monitoring rollout status deploy/prometheus --timeout=180s
  ok "k8s pronto: app http://127.0.0.1:30080  | ingress http://lab.localtest.me:8080 | Prometheus http://127.0.0.1:9090"
  info "tente: kubectl get nodes,pods -A   |   curl -s http://127.0.0.1:30080/info"
}

# ------------------------------------------------------------------ outros grupos
ensure_k8s() { cluster_running || { warn "cluster não está rodando; iniciando k8s primeiro"; start_k8s; }; }
start_observability() {
  ensure_k8s; container_running lab-grafana || { mem_check observability 900; port_check 3000 3100 3200; }
  mkdir -p "$LOGDIR"
  LAB_KIND_LOGDIR="$LOGDIR" run docker compose -f observability/docker-compose.yml up -d
  say "aguardando Grafana"; for _ in $(seq 40); do curl -fs http://127.0.0.1:3000/api/health >/dev/null && break; sleep 2; done
  say "aguardando Loki ficar ready (~20s)"; for _ in $(seq 40); do curl -fs http://127.0.0.1:3100/ready >/dev/null && break; sleep 2; done
  docker restart lab-alloy >/dev/null   # garante que o Alloy comece a enviar só depois do Loki estar pronto
  ok "Grafana http://127.0.0.1:3000 (dashboard 'Golden Signals — lab-app'; sem login) | Loki :3100 | Tempo :3200"
  info "gere tráfego: ./lab.sh traffic 120 5"
}
sync_repo() {   # repo git local que o Jenkins faz checkout (permite simular commits quebrados)
  local r="$DATA_DIR/app-repo"
  if [[ ! -d "$r/.git" ]]; then
    mkdir -p "$r"; cp -r app/. "$r"/; rm -rf "$r/__pycache__" "$r/.pytest_cache" "$r/tests/__pycache__"
    git -C "$r" init -q -b main; git -C "$r" config user.name "lab"; git -C "$r" config user.email "lab@local"
    git -C "$r" add -A; git -C "$r" commit -q -m "versão inicial do app"
    ok "repo local criado em $r"
  fi
}
start_cicd() {
  need_cluster; container_running lab-jenkins || { mem_check cicd 1600; port_check 8088; }
  mkdir -p "$DATA_DIR/secrets" "$TRIVY_CACHE_DIR"; sync_repo
  kind get kubeconfig --internal --name "$CLUSTER" > "$DATA_DIR/kubeconfig-internal"
  export DOCKER_GID; DOCKER_GID="$(getent group docker | cut -d: -f3)"; export LAB_DATA="$DATA_DIR"
  run docker compose -f cicd/docker-compose.yml up -d --build
  say "aguardando Jenkins (1-2 min)"; for _ in $(seq 90); do curl -fs -o /dev/null http://127.0.0.1:8088/login && break; sleep 3; done
  ok "Jenkins http://127.0.0.1:8088  (usuário admin / senha admin) — job 'lab-app'. Rode: ./lab.sh pipeline run"
}
start_security() {
  need docker; container_running lab-sonarqube || { mem_check security 2600; port_check 9000; }
  command -v docker >/dev/null; docker network inspect kind >/dev/null 2>&1 || run docker network create kind >/dev/null
  run docker compose -f security/docker-compose.yml up -d
  ok "SonarQube iniciando (2-3 min) em http://127.0.0.1:9000. Depois: ./lab.sh sonar-setup"
}
cmd_start() {
  case "${1:-}" in
    k8s) start_k8s;; observability) start_observability;; cicd) start_cicd;; security) start_security;;
    *) die "informe o grupo: k8s | observability | cicd | security   (não há 'all': a RAM não aguenta tudo junto)";;
  esac
}
stop_group() {
  case "$1" in
    observability) run docker compose -f observability/docker-compose.yml stop 2>/dev/null || true;;
    cicd) run docker compose -f cicd/docker-compose.yml stop 2>/dev/null || true;;
    security) run docker compose -f security/docker-compose.yml stop 2>/dev/null || true;;
    k8s) for n in "${CLUSTER}-worker" "${CLUSTER}-control-plane"; do container_running "$n" && run docker stop "$n" >/dev/null; done; true;;
    *) die "grupo inválido: $1";;
  esac
}
cmd_stop() {
  export LAB_KIND_LOGDIR="$LOGDIR" DOCKER_GID="$(getent group docker | cut -d: -f3)" LAB_DATA="$DATA_DIR"
  if [[ "${1:-all}" == all ]]; then for g in security cicd observability k8s; do stop_group $g; done; else stop_group "$1"; fi
  ok "parado. Dados preservados (use './lab.sh cleanup' para remover de verdade)."
}
cmd_status() {
  say "Grupos"
  cluster_running && ok "k8s            rodando" || info "k8s            parado"
  for p in "observability:lab-grafana" "cicd:lab-jenkins" "security:lab-sonarqube"; do
    container_running "${p#*:}" && ok "$(printf '%-14s' "${p%%:*}") rodando" || info "$(printf '%-14s' "${p%%:*}") parado"
  done
  say "Memória: $(free -m | awk '/Mem:/ {print $3" MB usados / "$2" MB; disponível "$7" MB"}')"
  docker ps --filter name='^lab-' --format '  {{.Names}}\t{{.Status}}' | sort
  if cluster_running; then say "Kubernetes"; kc get nodes; kc get pods -n demo; kc get ns -l lab-incident=true --no-headers 2>/dev/null | sed 's/^/  incidente ativo: /'; fi
}
cmd_urls() { cat <<EOT
App (NodePort)   http://127.0.0.1:30080          Ingress  http://lab.localtest.me:8080
Prometheus       http://127.0.0.1:9090           Grafana  http://127.0.0.1:3000  (sem login)
Jenkins          http://127.0.0.1:8088           admin / admin
SonarQube        http://127.0.0.1:9000           admin / $SONAR_PASS (após ./lab.sh sonar-setup)
Loki http://127.0.0.1:3100  | Tempo http://127.0.0.1:3200
EOT
}

# ------------------------------------------------------------------ reset / cleanup
cmd_reset() {
  need_cluster
  say "O reset fará:"; info "- remover namespaces de incidente (label lab-incident=true): $(kc get ns -l lab-incident=true -o name 2>/dev/null | tr '\n' ' ')"
  info "- reaplicar k8s/base e voltar lab-app para $APP_IMAGE"
  info "- NÃO toca em volumes, Jenkins, Sonar, Grafana nem em outros namespaces"
  confirm "Prosseguir?" || die "cancelado"
  kc delete ns -l lab-incident=true --wait=false 2>/dev/null || true
  kc apply -f k8s/base/ >/dev/null
  kc -n demo set image deploy/lab-app app="$APP_IMAGE" >/dev/null
  kc -n demo set env deploy/lab-app APP_VERSION=1.0.0 >/dev/null
  kc -n demo rollout status deploy/lab-app --timeout=120s
  ok "reset concluído"
}
cmd_cleanup() {
  export LAB_KIND_LOGDIR="$LOGDIR" DOCKER_GID="$(getent group docker | cut -d: -f3)" LAB_DATA="$DATA_DIR"
  local vol=""; [[ "${1:-}" == "--volumes" ]] && vol="-v"
  say "cleanup removerá:"
  info "- cluster Kind '$CLUSTER' (nodes lab-control-plane/lab-worker)"
  info "- containers dos grupos observability, cicd, security e os logs em .data/kind-logs"
  info "- containers e processos dos exercícios linux-* (lab-diskfull, lab-dnstest, lab-cpuhog, ...)"
  [[ -n "$vol" ]] && warn "- VOLUMES (Jenkins home, Sonar, Grafana, Loki, Tempo): dados serão PERDIDOS" || info "- volumes serão preservados (use --volumes para apagá-los)"
  info "- imagens/containers que NÃO são do lab (ex.: seus projetos) não são tocados"
  confirm "Confirmar?" || die "cancelado"
  cluster_exists && run kind delete cluster --name "$CLUSTER"
  for g in observability cicd security; do docker compose -f $g/docker-compose.yml down $vol 2>/dev/null || true; done
  # sobras dos exercícios linux-* (cada reset é idempotente)
  for ex in linux-cpu linux-disk linux-port linux-dns; do exercises/$ex/run.sh reset >/dev/null 2>&1 || true; done
  # os logs do Kind pertencem ao root (gravados pelo kubelet dentro do node): limpa via container descartável
  [[ -d "$LOGDIR" ]] && docker run --rm -v "$LOGDIR:/x" busybox:1.37 sh -c 'rm -rf /x/* 2>/dev/null' || true
  [[ -n "$vol" ]] && warn "Para apagar também .data/ (repo do Jenkins, tokens, caches): rm -rf .data  (comando manual, por segurança)"
  ok "cleanup concluído"
}

# ------------------------------------------------------------------ exercícios
cmd_exercise() {
  local name="${1:-list}" action="${2:-reproduce}"
  if [[ "$name" == list ]]; then
    say "Exercícios disponíveis"; for d in exercises/*/; do printf '  %-24s %s\n' "$(basename "$d")" "$(head -1 "$d/exercise.md" | sed 's/^# //')"; done; return
  fi
  [[ -x "exercises/$name/run.sh" ]] || die "exercício '$name' não existe. Veja: ./lab.sh exercise list"
  if [[ "$action" == guide ]]; then cat "exercises/$name/exercise.md"; return; fi
  [[ "$name" == linux-* ]] || [[ "$name" == vulnerable-image ]] || need_cluster
  exercises/"$name"/run.sh "$action"
}

cmd_traffic() {
  local secs="${1:-60}" rps="${2:-5}" base="${TARGET:-http://127.0.0.1:30080}" end
  end=$(( $(date +%s) + secs ))
  say "gerando ~$rps req/s em $base por ${secs}s (Ctrl-C interrompe)"
  while (( $(date +%s) < end )); do
    for _ in $(seq "$rps"); do curl -s -o /dev/null -m 10 "$base/api/work" & done
    curl -s -o /dev/null -m 5 "$base/api/hello" &
    sleep 1
  done; wait; ok "tráfego finalizado"
}

# ------------------------------------------------------------------ Jenkins / Sonar / scans / terraform
J=http://127.0.0.1:8088
jcurl() { curl -fsS -u "admin:${JENKINS_ADMIN_PASSWORD:-admin}" -b "$DATA_DIR/jar" -c "$DATA_DIR/jar" "$@"; }
cmd_pipeline() {
  [[ "${1:-run}" == run ]] || die "uso: ./lab.sh pipeline run [PARAM=valor]"; shift || true
  container_running lab-jenkins || die "Jenkins parado: ./lab.sh start cicd"
  local crumb n url="$J/job/lab-app/build" q=""
  crumb="$(jcurl "$J/crumbIssuer/api/json" | jq -r '.crumbRequestField+":"+.crumb')"
  (($#)) && q="$(IFS='&'; echo "$*")"
  # job com parâmetros (depois do 1º build) usa buildWithParameters; antes disso, /build
  if jcurl "$J/job/lab-app/api/json" | jq -e '.property[]?|select(.parameterDefinitions)' >/dev/null 2>&1; then url="$J/job/lab-app/buildWithParameters"; fi
  n="$(jcurl "$J/job/lab-app/api/json" | jq -r .nextBuildNumber)"
  say "disparando build #$n"
  jcurl -X POST -H "$crumb" "$url${q:+?$q}" -o /dev/null
  for _ in $(seq 60); do jcurl -o /dev/null "$J/job/lab-app/$n/api/json" 2>/dev/null && break; sleep 2; done
  local off=0 hdr
  while :; do
    hdr="$(mktemp)"; jcurl -D "$hdr" "$J/job/lab-app/$n/logText/progressiveText?start=$off" | sed 's/\x1b\[8mha:[^\x1b]*\x1b\[0m//g' || true
    off="$(awk -F': ' 'tolower($1)=="x-text-size" {gsub(/\r/,"",$2); print $2}' "$hdr")"; off="${off:-0}"
    grep -qi '^x-more-data' "$hdr" || { rm -f "$hdr"; break; }; rm -f "$hdr"; sleep 2
  done
  local res; res="$(jcurl "$J/job/lab-app/$n/api/json" | jq -r .result)"
  [[ "$res" == SUCCESS ]] && ok "build #$n: SUCCESS" || { err "build #$n: $res  ($J/job/lab-app/$n/console)"; return 1; }
}
cmd_sonar_setup() {
  container_running lab-sonarqube || die "SonarQube parado: ./lab.sh start security"
  local S=http://127.0.0.1:9000 tok
  say "aguardando SonarQube ficar UP"; for _ in $(seq 90); do curl -fs "$S/api/system/status" | grep -q '"UP"' && break; sleep 4; done
  curl -fs "$S/api/system/status" | grep -q '"UP"' || die "SonarQube não subiu a tempo; veja: docker logs lab-sonarqube"
  curl -fs -u "admin:admin" -X POST "$S/api/users/change_password" -d login=admin -d previousPassword=admin --data-urlencode "password=$SONAR_PASS" >/dev/null 2>&1 \
    && ok "senha do admin alterada" || info "senha já havia sido alterada"
  curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/user_tokens/revoke" -d name=lab >/dev/null 2>&1 || true
  tok="$(curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/user_tokens/generate" -d name=lab -d type=GLOBAL_ANALYSIS_TOKEN | jq -r .token)"
  mkdir -p "$DATA_DIR/secrets"; printf '%s' "$tok" > "$DATA_DIR/secrets/sonar-token"; chmod 600 "$DATA_DIR/secrets/sonar-token"
  ok "token salvo em .data/secrets/sonar-token (Jenkins o usa automaticamente)"
}
cmd_scan() {
  need trivy; [[ -f "$TRIVY_CACHE_DIR/db/trivy.db" ]] || die "banco do Trivy ausente: ./lab.sh install"
  local what="${1:-}"; shift || true
  case "$what" in
    fs) run trivy fs --skip-db-update --scanners vuln,secret,misconfig "${@:-app}";;
    image) run trivy image --skip-db-update "${@:-$APP_IMAGE}";;
    sample) run trivy fs --skip-db-update --scanners vuln,secret,misconfig security/samples/vulnerable-app;;
    sonar-sample)   # SAST real do SonarQube sobre o código inseguro de demonstração
      need sonar-scanner; [[ -s "$DATA_DIR/secrets/sonar-token" ]] || die "rode antes: ./lab.sh start security && ./lab.sh sonar-setup"
      local S=http://127.0.0.1:9000 T; T="$(cat "$DATA_DIR/secrets/sonar-token")"
      # Quality Gate "Lab strict": reprova se houver QUALQUER vulnerabilidade (código inteiro, não só código novo)
      curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/projects/create" -d project=vulnerable-sample -d "name=Vulnerable Sample (demonstrativo)" >/dev/null 2>&1 || true
      if curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/qualitygates/create" -d "name=Lab strict" >/dev/null 2>&1; then
        curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/qualitygates/create_condition" -d "gateName=Lab strict" -d metric=vulnerabilities -d op=GT -d error=0 >/dev/null
      fi
      curl -fs -u "admin:$SONAR_PASS" -X POST "$S/api/qualitygates/select" -d "gateName=Lab strict" -d projectKey=vulnerable-sample >/dev/null || warn "não consegui associar o gate 'Lab strict'"
      (cd security/samples/vulnerable-app && SONAR_TOKEN="$T" sonar-scanner -Dsonar.host.url=$S -Dsonar.qualitygate.wait=true) || warn "Quality Gate reprovou (esperado neste exemplo)"
      ok "resultados em $S/dashboard?id=vulnerable-sample";;
    *) die "uso: ./lab.sh scan <fs [dir]|image [img]|sample|sonar-sample>";;
  esac
}
cmd_tf() {
  need terraform; local ex="${1:?uso: ./lab.sh tf <01|02> <comando>}"; shift
  local dir; dir="$(ls -d terraform/"$ex"* 2>/dev/null | head -1)"; [[ -n "$dir" ]] || die "exercício terraform '$ex' inexistente"
  mkdir -p "$DATA_DIR/tf-plugin-cache"; sed "s#__LAB__#$LAB_DIR#" terraform/terraformrc > "$DATA_DIR/terraformrc"
  [[ "$ex" == 02* ]] && { cluster_running || die "o exercício 02 precisa do cluster: ./lab.sh start k8s"; }
  TF_CLI_CONFIG_FILE="$DATA_DIR/terraformrc" run terraform -chdir="$dir" "$@"
}

main() {
  local c="${1:-help}"; shift || true
  case "$c" in
    check) cmd_check;; install) cmd_install "$@";; start) cmd_start "${1:-}";; stop) cmd_stop "${1:-all}";;
    status) cmd_status;; reset) cmd_reset;; cleanup) cmd_cleanup "${1:-}";; exercise) cmd_exercise "$@";;
    traffic) cmd_traffic "$@";; pipeline) cmd_pipeline "$@";; sonar-setup) cmd_sonar_setup;; scan) cmd_scan "$@";;
    tf) cmd_tf "$@";; urls) cmd_urls;; help|-h|--help) usage;; *) usage; die "comando desconhecido: $c";;
  esac
}
main "$@"
