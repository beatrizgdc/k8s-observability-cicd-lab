#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: imagem Docker com vulnerabilidades (código/Dockerfile de demonstração INSEGUROS de propósito).
# Os números vêm do Trivy de verdade, executado sobre a imagem construída aqui.
need docker; need trivy
SRC="$LAB_DIR/security/samples/vulnerable-app"; FIX="$LAB_DIR/exercises/vulnerable-image/fixed"
count() { trivy image --skip-db-update -q --format json "$1" | jq '[.Results[]?.Vulnerabilities[]?] | group_by(.Severity) | map({(.[0].Severity): length}) | add'; }
case "${1:-reproduce}" in
  reproduce)
    say "Construindo lab-vuln:demo (base antiga + dependências antigas)"
    run docker build -q -t lab-vuln:demo "$SRC"
    say "Scan da imagem (resumo por severidade) — Trivy real:"
    count lab-vuln:demo
    info "Detalhes: ./lab.sh scan image lab-vuln:demo   |   só críticas: trivy image --skip-db-update --severity CRITICAL lab-vuln:demo"
    info "Dependências: ./lab.sh scan sample";;
  fix)
    say "Construindo lab-vuln:fixed (base e dependências atualizadas)"
    run docker build -q -t lab-vuln:fixed "$FIX"
    say "ANTES:"; count lab-vuln:demo; say "DEPOIS:"; count lab-vuln:fixed;;
  validate)
    say "Critérios: nenhuma vulnerabilidade CRITICAL na imagem corrigida"
    trivy image --skip-db-update --severity CRITICAL --exit-code 1 -q lab-vuln:fixed && ok "0 CRITICAL em lab-vuln:fixed";;
  reset) docker rmi lab-vuln:demo lab-vuln:fixed 2>&1 | sed 's/^/  /' || true;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
