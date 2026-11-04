#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Exercício Linux: "a internet caiu?" — rede OK, DNS quebrado. Usa um container com resolvedor inexistente.
need docker
C=lab-dnstest
case "${1:-reproduce}" in
  reproduce)
    docker rm -f $C >/dev/null 2>&1 || true
    run docker run -d --name $C --dns 10.255.255.1 busybox:1.37 sleep 3600 >/dev/null
    GW="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}')"
    say "1) Conectividade por IP (gateway do Docker $GW):"; docker exec $C ping -c1 -W2 "$GW" | tail -2
    say "2) Resolução de nome (deve falhar):";     docker exec $C nslookup -timeout=2 example.com || warn "falhou como esperado"
    say "3) /etc/resolv.conf do container:";       docker exec $C cat /etc/resolv.conf
    info "Conclusão a tirar: ping por IP funciona, nome não => problema de DNS, não de rede.";;
  fix)
    say "Recriando o container com o DNS do host/daemon (padrão)"
    docker rm -f $C >/dev/null; run docker run -d --name $C busybox:1.37 sleep 3600 >/dev/null
    docker exec $C cat /etc/resolv.conf;;
  validate) docker exec $C nslookup -timeout=3 example.com && ok "DNS resolvendo (requer internet nesta etapa)";;
  reset) docker rm -f $C 2>&1 | sed 's/^/  removido: /';;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
