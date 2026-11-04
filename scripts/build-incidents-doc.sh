#!/usr/bin/env bash
# Gera docs/08-INCIDENTS-RCA.md juntando exercises/*/exercise.md (fonte única de verdade) + modelo de RCA.
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out=docs/08-INCIDENTS-RCA.md
{
cat <<'HEAD'
# 08 — Troubleshooting e Incidentes (com RCA)

> Este arquivo é **gerado** por `scripts/build-incidents-doc.sh` a partir de `exercises/*/exercise.md`.
> Edite os guias em `exercises/<nome>/exercise.md` e rode o script novamente.

Cada incidente é **isolado** (namespace próprio `inc-<nome>` ou container próprio) e **reversível** (`reset`).
Comandos de qualquer exercício:

```bash
./lab.sh exercise list
./lab.sh exercise <nome>            # reproduz o incidente
./lab.sh exercise <nome> fix        # aplica a correção
./lab.sh exercise <nome> validate   # confirma a recuperação
./lab.sh exercise <nome> reset      # remove tudo que o exercício criou
./lab.sh exercise <nome> guide      # imprime o roteiro no terminal
```

**Método geral de investigação (use em todos):**
1. *Qual o sintoma e desde quando?* (alerta, usuário, métrica)  2. *O que mudou?* (deploy, config, tráfego)
3. *Qual o escopo?* (um pod, todos, um node, um serviço)  4. *Onde está o primeiro erro?* (eventos, logs, métricas)
5. *Mitigar primeiro, corrigir depois.*  6. *Validar com a mesma métrica que alertou.*  7. *Registrar o RCA.*

## Sumário
HEAD
n=0
for d in exercises/*/; do n=$((n+1)); name=$(basename "$d"); title=$(head -1 "$d/exercise.md" | sed 's/^# //'); echo "$n. [\`$name\` — $title](#$name)"; done
echo
n=0
for d in exercises/*/; do
  n=$((n+1)); name=$(basename "$d")
  echo "---"; echo; echo "<a id=\"$name\"></a>"; echo
  sed -e '1s/^# /## '"$n"'. /' -e 's/^## \([A-ZÁÉÍÓÚ]\)/### \1/' "$d/exercise.md" | sed '1s/^### /## /'
  echo
done
cat <<'RCA'
---

## Modelo de RCA reutilizável (Root Cause Analysis / Post-mortem)

Copie, preencha e arquive. Regras: **sem culpados** (blameless), fatos com horário, causa em sistema/processo, ações com dono e prazo.

```markdown
# RCA — <título curto> — <data>

**Severidade:** SEV1/2/3  **Duração:** hh:mm  **Autor:** <nome>  **Status:** rascunho/final

## 1. Resumo (2-3 linhas)
O que aconteceu, quem foi afetado e qual foi o impacto de negócio.

## 2. Impacto
- Usuários/serviços afetados:        - Métricas (erro %, latência, requisições perdidas):
- SLO/Error budget consumido:        - Impacto financeiro/contratual (se houver):

## 3. Linha do tempo (UTC-3)
| Hora  | Evento |
|-------|--------|
| hh:mm | Mudança/deploy X aplicada |
| hh:mm | Alerta Y disparou |
| hh:mm | Incidente declarado; <pessoa> assume como IC |
| hh:mm | Mitigação aplicada (ex.: rollback) |
| hh:mm | Serviço recuperado e validado |

## 4. Detecção
Como descobrimos? (alerta, cliente, ronda). Tempo até detectar (TTD): ___ . Poderíamos ter detectado antes?

## 5. Causa-raiz e fatores contribuintes
- Causa-raiz (use os "5 porquês"): ...
- Fatores contribuintes (falta de teste, alerta ausente, doc desatualizada...): ...
- O que **deu certo**: ...

## 6. Mitigação e resolução
O que foi feito, comandos relevantes, tempo até mitigar (TTM): ___ .

## 7. Validação da recuperação
Quais métricas/consultas comprovam que voltou ao normal?

## 8. Ações corretivas e preventivas
| Ação | Tipo (prevenir/detectar/mitigar) | Dono | Prazo | Ticket |
|------|------|------|------|------|

## 9. Lições aprendidas
...
```

**Os 5 porquês (exemplo — CrashLoopBackOff):** Por que o serviço caiu? O pod reiniciava. Por quê? Saía com código 3. Por quê? Faltava `DATABASE_URL`. Por quê? O manifesto novo não a incluía. Por quê? Não há validação de variáveis obrigatórias no CI. → ação: validar config no pipeline.

**Métricas de incidente:** TTD (detecção), TTA (reconhecimento), TTM (mitigação), TTR (resolução), MTTR médio.
RCA
} > "$out"
echo "gerado: $out ($(wc -l < "$out") linhas)"
