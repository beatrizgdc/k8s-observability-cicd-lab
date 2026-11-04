#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
# Incidente: um commit "inocente" quebra o teste e a pipeline Jenkins falha no estágio Test.
REPO="$DATA_DIR/app-repo"
case "${1:-reproduce}" in
  reproduce)
    container_running lab-jenkins || die "Jenkins parado. Rode: ./lab.sh start cicd"
    [[ -d "$REPO/.git" ]] || die "repo do Jenkins não existe (./lab.sh start cicd cria)"
    say "Commit 'inocente': troca a mensagem de /api/hello (mas o teste espera 'olá...')"
    sed -i 's/olá do lab/hello from lab/' "$REPO/app.py"
    git -C "$REPO" commit -qam "feat: internacionaliza mensagem do /api/hello"
    git -C "$REPO" log --oneline | head -3
    say "Disparando a pipeline (vai FALHAR; o log será exibido)"
    "$LAB_DIR/lab.sh" pipeline run || true
    info "Investigue o estágio vermelho no Jenkins: http://127.0.0.1:8088/job/lab-app/ (Console Output / Test Result)";;
  fix)
    say "Correção segura: git revert do commit ruim (mantém o histórico)"
    run git -C "$REPO" revert --no-edit HEAD
    info "Agora rode a pipeline: ./lab.sh pipeline run   (ou ./lab.sh exercise jenkins-pipeline-fail validate)";;
  validate) "$LAB_DIR/lab.sh" pipeline run;;
  reset)
    if git -C "$REPO" log -1 --pretty=%s | grep -q internacionaliza; then run git -C "$REPO" revert --no-edit HEAD; else info "nada a reverter"; fi;;
  *) die "ações: reproduce|fix|validate|reset|guide";;
esac
