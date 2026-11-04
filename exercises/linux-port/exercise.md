# Linux: porta já em uso

## Objetivo
Descobrir qual processo ocupa uma porta com `ss`, e liberar com segurança.

## Contexto do incidente
O deploy da nova versão falha: `OSError: [Errno 98] Address already in use` na porta 8099.

## Como reproduzir
`./lab.sh exercise linux-port` (sobe um servidor `lab-port-holder` na 8099 e tenta subir outro).

## Investigação
```bash
ss -ltnp 'sport = :8099'          # -l listening, -t TCP, -n numérico, -p processo (PID/nome)
ps -fp <PID>                      # quem é, quem iniciou, há quanto tempo
curl -sI http://127.0.0.1:8099    # o que está respondendo?
nc -zv 127.0.0.1 8099             # a porta aceita conexão?
```
**Como interpretar:** `LISTEN 127.0.0.1:8099 users:(("python3",pid=...))`. `127.0.0.1` = só local; `0.0.0.0`/`*` = todas as interfaces.

## Causa-raiz
Instância antiga (ou outro processo) ainda escutando a porta.

## Como resolver
`kill <PID>` (ou `./lab.sh exercise linux-port fix`). Confirme que o processo é o que você pensa antes de matar.

## Como validar
`ss -ltn 'sport = :8099'` sem resultado; `./lab.sh exercise linux-port validate`.

## Limpeza / Perguntas
`./lab.sh exercise linux-port reset`. Perguntas: TIME_WAIT é problema? `ss` vs `netstat`? Como achar o dono sem `-p` (sem root)? `SO_REUSEADDR`?
