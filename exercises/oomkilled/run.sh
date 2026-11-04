#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: container morto por OOMKilled (limit de memória 64Mi, app aloca 150MB).
NS=inc-oomkilled
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: leaky }
spec:
  replicas: 1
  selector: { matchLabels: { app: leaky } }
  template:
    metadata:
      labels: { app: leaky }
      annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          resources: { requests: { cpu: 10m, memory: 64Mi }, limits: { memory: 100Mi } }
YAML
    run kc -n $NS rollout status deploy/leaky --timeout=90s
    say "Disparando a requisição que 'vaza' memória (/memory?mb=150) — o container deve ser morto"
    inc_call $NS leaky "/memory?mb=150" || warn "conexão cortada: o processo foi morto (esperado)"
    sleep 5; kc -n $NS get pods
    info "Investigue: kubectl -n $NS describe pod -l app=leaky | grep -A6 'Last State'";;
  fix)
    say "Mitigação: aumentar o limit de memória para 300Mi (correção real: corrigir o vazamento no código)"
    run kc -n $NS set resources deploy/leaky --limits=memory=300Mi --requests=memory=128Mi
    run kc -n $NS rollout status deploy/leaky --timeout=90s;;
  validate)
    run kc -n $NS rollout status deploy/leaky --timeout=60s
    inc_call $NS leaky "/memory?mb=150" && ok "150MB alocados sem OOMKilled"
    kc -n $NS get pods -l app=leaky; info "RESTARTS do pod novo deve ser 0";;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
