#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: CPU alta / throttling num pod com limit de 200m.
NS=inc-high-cpu
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: burner }
spec:
  replicas: 1
  selector: { matchLabels: { app: burner } }
  template:
    metadata:
      labels: { app: burner }
      annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          resources: { requests: { cpu: 100m, memory: 64Mi }, limits: { cpu: 200m, memory: 192Mi } }
YAML
    run kc -n $NS rollout status deploy/burner --timeout=90s
    say "Disparando /cpu?seconds=900 (queima CPU por 15 min em segundo plano)"
    inc_call $NS burner "/cpu?seconds=900"
    info "Aguarde ~60s (metrics-server) e rode: kubectl -n $NS top pod";;
  fix)
    say "Mitigação imediata: reiniciar o pod (mata a thread descontrolada). Correção real: achar a requisição/código causador."
    run kc -n $NS rollout restart deploy/burner
    run kc -n $NS rollout status deploy/burner --timeout=90s;;
  validate) sleep 20; kc -n $NS top pod || warn "metrics ainda não disponíveis; aguarde 30s";;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
