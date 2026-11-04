#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: a latência de /api/work saltou para ~1,5 s após uma mudança de configuração.
NS=inc-high-latency
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: api-config }
data: { FAULT_LATENCY_MS: "1500" }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: api }
spec:
  replicas: 2
  selector: { matchLabels: { app: api } }
  template:
    metadata:
      labels: { app: api }
      annotations: { prometheus.io/scrape: "true", prometheus.io/port: "8080" }
    spec:
      containers:
        - name: app
          image: lab-app:1.0.0
          imagePullPolicy: IfNotPresent
          envFrom: [{ configMapRef: { name: api-config } }]
          readinessProbe: { httpGet: { path: /readyz, port: 8080 } }
          resources: { requests: { cpu: 20m, memory: 64Mi }, limits: { cpu: 250m, memory: 192Mi } }
---
apiVersion: v1
kind: Service
metadata: { name: api }
spec:
  selector: { app: api }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: load }
spec:
  replicas: 1
  selector: { matchLabels: { app: load } }
  template:
    metadata: { labels: { app: load } }
    spec:
      containers:
        - name: load
          image: busybox:1.37
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "while true; do wget -q -O /dev/null -T 10 http://api/api/work || true; sleep 0.3; done"]
          resources: { requests: { cpu: 5m, memory: 8Mi } }
YAML
    run kc -n $NS rollout status deploy/api --timeout=90s
    ok "Incidente ativo. Há um gerador de tráfego (deployment 'load') chamando o Service api."
    info "Suspeite pelos sintomas e investigue (logs, métricas no Grafana/Prometheus). Roteiro: ./lab.sh exercise high-latency guide";;
  fix)
    say "Corrigindo a configuração e REINICIANDO os pods (variáveis de ConfigMap só são lidas na inicialização!)"
    run kc -n $NS patch configmap api-config --type merge -p '{"data":{"FAULT_LATENCY_MS":"0"}}'
    run kc -n $NS rollout restart deploy/api
    run kc -n $NS rollout status deploy/api --timeout=90s;;
  validate)
    sleep 5; say "5 chamadas a /api/work (todas devem ser rápidas e HTTP 200):"
    for i in 1 2 3 4 5; do kc -n $NS exec deploy/load -- sh -c 'wget -S -O /dev/null -T 10 http://api/api/work 2>&1 | grep -E "HTTP/|real"' ; done
    kc -n $NS logs -l app=api --tail=5 --prefix;;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
