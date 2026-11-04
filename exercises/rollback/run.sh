#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: deploy da versão 2.0.0 quebrada; o rollout trava e é preciso fazer rollback.
NS=inc-rollback
v1() { cat <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  annotations: { kubernetes.io/change-cause: "v1.0.0 - versão estável" }
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy: { type: RollingUpdate, rollingUpdate: { maxSurge: 1, maxUnavailable: 0 } }
  selector: { matchLabels: { app: shop } }
  template:
    metadata: { labels: { app: shop } }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          env: [{ name: APP_VERSION, value: "1.0.0" }]
          readinessProbe: { httpGet: { path: /readyz, port: 8080 }, periodSeconds: 3 }
          livenessProbe:  { httpGet: { path: /healthz, port: 8080 }, periodSeconds: 5 }
          resources: { requests: { cpu: 10m, memory: 64Mi } }
YAML
}
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    say "Passo 1: deploy da v1.0.0 (estável)"
    v1 | kc -n $NS apply -f -; run kc -n $NS rollout status deploy/shop --timeout=90s
    say "Passo 2: deploy da v2.0.0 — com um bug que faz /readyz e /healthz falharem"
    v1 | sed -e 's/v1.0.0 - versão estável/v2.0.0 - nova feature (BUGADA)/' -e 's/value: "1.0.0"/value: "2.0.0"/' \
          -e 's#^          env: .*#          env: [{ name: APP_VERSION, value: "2.0.0" }, { name: FAIL_HEALTH, value: "1" }]#' | kc -n $NS apply -f -
    sleep 15; kc -n $NS get pods
    warn "Rollout travado: 'kubectl -n $NS rollout status deploy/shop' ficará esperando. maxUnavailable=0 manteve a v1 atendendo."
    info "Investigue: rollout status/history, get rs, describe pod, events";;
  fix)
    say "Rollback para a revisão anterior"
    run kc -n $NS rollout undo deploy/shop
    run kc -n $NS rollout status deploy/shop --timeout=90s;;
  validate)
    kc -n $NS rollout history deploy/shop
    inc_call $NS shop /info; kc -n $NS get pods;;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
