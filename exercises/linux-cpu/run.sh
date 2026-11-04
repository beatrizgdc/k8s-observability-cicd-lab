#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Exercício Linux: processos consumindo CPU (2 loops "lab-cpuhog", limitados a 2 núcleos e nice 10).
PIDF="$DATA_DIR/linux-cpu.pids"; mkdir -p "$DATA_DIR"
kill_hogs() {
  [[ -f "$PIDF" ]] || { info "nenhum processo registrado"; return; }
  while read -r p; do
    if [[ -r /proc/$p/cmdline ]] && tr '\0' ' ' < /proc/$p/cmdline | grep -q lab-cpuhog; then kill "$p" && info "encerrado PID $p"; fi
  done < "$PIDF"; rm -f "$PIDF"
}
case "${1:-reproduce}" in
  reproduce)
    [[ -f "$PIDF" ]] && die "já em execução. Use: ./lab.sh exercise linux-cpu fix"
    for i in 1 2; do ( exec nice -n 10 bash -c 'while :; do :; done # lab-cpuhog' </dev/null >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 & echo $! >> "$PIDF"; done
    sleep 1; ok "2 processos 'lab-cpuhog' iniciados (PIDs: $(tr '\n' ' ' < "$PIDF"))"
    info "Investigue com: top -o %CPU   |   ps -eo pid,ni,pcpu,etime,cmd --sort=-pcpu | head   |   uptime";;
  fix) kill_hogs; sleep 1; uptime;;
  validate) ps -eo pid,pcpu,cmd --sort=-pcpu | head -5; pgrep -f '^bash -c while :; do :; done # lab-cpuhog' >/dev/null && err "ainda há lab-cpuhog" || ok "nenhum lab-cpuhog em execução";;
  reset) kill_hogs;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
