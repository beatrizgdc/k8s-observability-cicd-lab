#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: pod em CrashLoopBackOff porque falta uma variável de ambiente obrigatória.
NS=inc-kubernetes-crashloop
case "${1:-reproduce}" in
  reproduce)
    say "Criando namespace $NS e um Deployment que exige DATABASE_URL (que NÃO será definida)"
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: orders-api }
spec:
  replicas: 1
  selector: { matchLabels: { app: orders-api } }
  template:
    metadata: { labels: { app: orders-api } }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          env: [{ name: REQUIRED_CONFIG, value: DATABASE_URL }]
          resources: { requests: { cpu: 10m, memory: 32Mi }, limits: { memory: 128Mi } }
YAML
    info "Aguarde ~60s e investigue:  kubectl -n $NS get pods -w"
    info "Roteiro completo: ./lab.sh exercise kubernetes-crashloop guide";;
  fix)
    say "Corrigindo: definindo DATABASE_URL no Deployment"
    run kc -n $NS set env deploy/orders-api DATABASE_URL=postgres://db.exemplo:5432/orders
    run kc -n $NS rollout status deploy/orders-api --timeout=90s;;
  validate)
    run kc -n $NS rollout status deploy/orders-api --timeout=60s && kc -n $NS get pods && ok "pod Ready e sem restarts crescentes";;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
