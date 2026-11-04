#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Exercício Linux: "Address already in use" — alguém já ocupa a porta 8099.
PIDF="$DATA_DIR/linux-port.pid"; mkdir -p "$DATA_DIR"
stop_holder() {
  if [[ -f "$PIDF" ]] && tr '\0' ' ' < /proc/$(cat "$PIDF")/cmdline 2>/dev/null | grep -q lab-port-holder; then kill "$(cat "$PIDF")" && info "encerrado PID $(cat "$PIDF")"; fi; rm -f "$PIDF"
}
case "${1:-reproduce}" in
  reproduce)
    port_in_use 8099 && die "porta 8099 já está em uso por outro processo seu; libere-a antes"
    ( cd /tmp && exec -a lab-port-holder python3 -m http.server 8099 --bind 127.0.0.1 >/dev/null 2>&1 ) & echo $! > "$PIDF"; sleep 1
    say "Tentando subir 'a nova versão do serviço' na 8099:"
    python3 -m http.server 8099 --bind 127.0.0.1 2>&1 | tail -1 || true
    info "Investigue: ss -ltnp 'sport = :8099'  |  curl -sI http://127.0.0.1:8099  |  ps -fp <PID>";;
  fix) stop_holder; sleep 1; port_in_use 8099 && err "porta ainda ocupada" || ok "porta 8099 livre";;
  validate) port_in_use 8099 && err "8099 ainda ocupada" || ok "8099 livre";;
  reset) stop_holder;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
