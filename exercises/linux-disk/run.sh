#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Exercício Linux: disco cheio de verdade, dentro de um container com tmpfs de 64MB (não afeta o seu disco).
need docker
C=lab-diskfull
case "${1:-reproduce}" in
  reproduce)
    docker rm -f $C >/dev/null 2>&1 || true
    run docker run -d --name $C --tmpfs /data:size=64m busybox:1.37 sleep 3600 >/dev/null
    docker exec $C sh -c 'mkdir -p /data/app/logs /data/app/cache; dd if=/dev/zero of=/data/app/logs/app.log bs=1M count=40 2>/dev/null;
      dd if=/dev/zero of=/data/app/cache/blob1 bs=1M count=10 2>/dev/null; echo "debug" > /data/app/logs/small.log'
    say "Tentando gravar mais 30MB (vai falhar com 'No space left on device'):"
    docker exec $C sh -c 'dd if=/dev/zero of=/data/app/cache/blob2 bs=1M count=30' || warn "falhou como esperado"
    info "Investigue: docker exec $C df -h /data ; docker exec $C du -ah /data | sort -h | tail ; docker exec $C df -i /data";;
  fix)
    say "Removendo o log gigante (em produção: rotacionar/comprimir, nunca apagar sem entender a causa)"
    run docker exec $C sh -c ': > /data/app/logs/app.log'     # truncar libera espaço mesmo se o processo mantém o arquivo aberto
    docker exec $C df -h /data;;
  validate) docker exec $C dd if=/dev/zero of=/data/app/cache/blob2 bs=1M count=30 2>&1 | tail -1 && ok "gravação voltou a funcionar"; docker exec $C df -h /data;;
  reset) docker rm -f $C 2>&1 | sed 's/^/  removido: /';;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
