#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: pod em ErrImagePull/ImagePullBackOff por erro de digitação na tag da imagem.
NS=inc-imagepull-backoff
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: checkout }
spec:
  replicas: 1
  selector: { matchLabels: { app: checkout } }
  template:
    metadata: { labels: { app: checkout } }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.O          # <- ERRO: letra O em vez do número 0
          imagePullPolicy: IfNotPresent
YAML
    info "Aguarde ~30s: kubectl -n $NS get pods ; kubectl -n $NS describe pod -l app=checkout | tail -15";;
  fix)
    run kc -n $NS set image deploy/checkout app=lab-app:1.0.0
    run kc -n $NS rollout status deploy/checkout --timeout=90s;;
  validate) kc -n $NS get pods;;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
