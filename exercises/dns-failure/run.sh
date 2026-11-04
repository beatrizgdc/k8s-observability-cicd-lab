#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: pod não resolve nomes (dnsPolicy None com nameserver inexistente); outro pod do mesmo ns funciona.
NS=inc-dns-failure
case "${1:-reproduce}" in
  reproduce)
    inc_ns_create $NS
    cat <<'YAML' | kc -n $NS apply -f -
apiVersion: v1
kind: Pod
metadata: { name: client-ok }
spec:
  containers: [{ name: c, image: "busybox:1.37", command: ["sleep", "3600"] }]
---
apiVersion: v1
kind: Pod
metadata: { name: client-broken }
spec:
  dnsPolicy: "None"
  dnsConfig: { nameservers: ["10.255.255.1"] }      # <- servidor DNS que não existe
  containers: [{ name: c, image: "busybox:1.37", command: ["sleep", "3600"] }]
---
apiVersion: v1
kind: Service
metadata: { name: alvo }
spec:
  selector: { app: alvo }
  ports: [{ port: 80 }]
YAML
    run kc -n $NS wait --for=condition=Ready pod --all --timeout=90s
    say "client-ok:";     kc -n $NS exec client-ok -- nslookup alvo.$NS.svc.cluster.local || true
    say "client-broken (deve falhar/timeout em ~15s):"; kc -n $NS exec client-broken -- nslookup -timeout=3 alvo.$NS.svc.cluster.local || warn "falhou como esperado"
    info "Compare: kubectl -n $NS exec client-ok -- cat /etc/resolv.conf   vs   client-broken";;
  fix)
    say "Recriando o pod com a política DNS padrão (ClusterFirst)"
    run kc -n $NS delete pod client-broken --wait=true
    kc -n $NS run client-broken --image=busybox:1.37 --image-pull-policy=IfNotPresent --command -- sleep 3600
    run kc -n $NS wait --for=condition=Ready pod/client-broken --timeout=60s;;
  validate) kc -n $NS exec client-broken -- nslookup alvo.$NS.svc.cluster.local && ok "DNS resolvendo";;
  reset) inc_ns_delete $NS;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
