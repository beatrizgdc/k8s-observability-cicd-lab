# Linux: processos consumindo CPU

## Objetivo
Achar rapidamente quem consome CPU e entender load average, `nice` e sinais.

## Contexto do incidente
O servidor (sua máquina) está lento e o ventilador disparou.

## Como reproduzir
`./lab.sh exercise linux-cpu` — inicia 2 loops `lab-cpuhog` (nice 10, 100% de 2 núcleos cada um).

## Investigação
```bash
uptime                                            # load average maior que o nº de CPUs ($(nproc)) = fila de execução
top -o %CPU                                       # (q sai) ordene por CPU; 'H' mostra threads; '1' mostra por núcleo
ps -eo pid,ppid,ni,pcpu,etime,cmd --sort=-pcpu | head -5
pgrep -af lab-cpuhog
cat /proc/<PID>/status | grep -E "State|Threads"
```
**Como interpretar:** `%CPU` ~100 por processo = 1 núcleo cheio. `NI 10` = prioridade baixa (cede CPU a outros). `load average` (1/5/15 min) sobe com processos prontos para rodar. `us` alto no `top` = CPU em user space; `sy` alto = kernel; `wa` alto = esperando disco (não é CPU real).

## Causa-raiz
Dois processos em loop infinito (`while :; do :; done`).

## Como resolver
```bash
kill <PID>          # SIGTERM (pede para encerrar)
kill -9 <PID>       # SIGKILL (último recurso)
# ou o atalho do lab:
./lab.sh exercise linux-cpu fix
```

## Como validar
`./lab.sh exercise linux-cpu validate` e `uptime` (load cai gradualmente).

## Modelo de RCA / perguntas
Causa: loop sem sleep. Prevenção: limites (cgroups/ulimit), alertas de CPU/load. Perguntas: load alto com CPU baixa? (I/O wait ou D-state.) Diferença entre `kill` e `kill -9`? O que é processo zumbi?
