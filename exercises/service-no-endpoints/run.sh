#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: Service existe mas não chega nos pods (selector com erro de digitação).
NS=inc-service-no-endpoints
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 2
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          readinessProbe: { httpGet: { path: /readyz, port: 8080 } }
          resources: { requests: { cpu: 10m, memory: 32Mi } }
---
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: webapp }          # <- ERRO: o label dos pods é app=web
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: v1
kind: Pod
metadata: { name: client }
spec:
  containers: [{ name: c, image: "busybox:1.37", command: ["sleep", "3600"] }]
YAML
    run kc -n $NS wait --for=condition=Ready pod --all --timeout=90s
    say "Testando a partir do pod client (deve falhar):"
    kc -n $NS exec client -- wget -qO- -T 3 http://web/api/hello || warn "falhou como esperado"
    info "Investigue: kubectl -n $NS get svc,endpoints,pods --show-labels";;
  fix)
    run kc -n $NS patch svc web -p '{"spec":{"selector":{"app":"web"}}}';;
  validate)
    kc -n $NS get endpoints web; kc -n $NS exec client -- wget -qO- -T 5 http://web/api/hello && ok "Service respondendo";;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
