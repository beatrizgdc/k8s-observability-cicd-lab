#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: pod Pending porque os requests excedem a capacidade de qualquer node.
NS=inc-pending-pod
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: bigapp }
spec:
  replicas: 1
  selector: { matchLabels: { app: bigapp } }
  template:
    metadata: { labels: { app: bigapp } }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          resources:
            requests: { cpu: "64", memory: 256Gi }     # <- pede muito mais do que qualquer node tem
YAML
    sleep 5; kc -n $NS get pods
    info "Investigue: kubectl -n $NS describe pod -l app=bigapp | tail -8 ; kubectl describe nodes | grep -A8 'Allocatable'";;
  fix)
    run kc -n $NS set resources deploy/bigapp --requests=cpu=50m,memory=64Mi
    run kc -n $NS rollout status deploy/bigapp --timeout=90s;;
  validate) kc -n $NS get pods -o wide;;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
