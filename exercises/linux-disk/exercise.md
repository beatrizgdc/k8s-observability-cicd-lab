# Linux: disco cheio

## Objetivo
Diagnosticar "No space left on device" com `df`, `du`, `find` (e inodes).

## Contexto do incidente
A aplicação para de gravar logs e dá erro de escrita. (O exercício usa um container com `tmpfs` de 64 MB — o disco real da sua máquina não é afetado.)

## Como reproduzir
`./lab.sh exercise linux-disk` (container `lab-diskfull`).

## Investigação
```bash
docker exec lab-diskfull df -h /data                   # Use% alto
docker exec lab-diskfull df -i /data                   # inodes (arquivos) — também podem esgotar
docker exec lab-diskfull du -ah /data | sort -h | tail # maiores arquivos/diretórios
docker exec lab-diskfull find /data -type f -size +5000k
# no seu host, o mesmo raciocínio:  df -h ;  du -xh / --max-depth=1 2>/dev/null | sort -h | tail ;  sudo find / -xdev -size +500M
```
**Como interpretar:** `df` diz *quanto* está usado por filesystem; `du` diz *onde*. `Use% 100` = cheio. Se `df` mostra espaço mas grava falha, olhe `df -i`. Arquivo apagado mas ainda aberto por processo não libera espaço (`lsof +L1`).

## Causa-raiz
Um `app.log` de 40 MB nunca rotacionado.

## Como resolver
`./lab.sh exercise linux-disk fix` (= `: > app.log`, truncar libera espaço mesmo com o arquivo aberto). Em produção: logrotate, retenção, enviar logs ao Loki.

## Como validar
`./lab.sh exercise linux-disk validate`.

## Limpeza / Perguntas
`./lab.sh exercise linux-disk reset`. Perguntas: `rm` vs truncar arquivo aberto? Como achar quem segura um arquivo deletado? Como prevenir (logrotate, alertas em 80%)?
