# 02 — Linux e Redes

Execute os comandos no seu terminal (KDE Neon). Os exercícios guiados são `./lab.sh exercise linux-cpu | linux-disk | linux-port | linux-dns` (veja [08](08-INCIDENTS-RCA.md)). Comandos marcados com 🔒 pedem `sudo` para ver tudo.

**Roteiro mental de diagnóstico (USE method):** para cada recurso — CPU, memória, disco, rede — olhe **U**tilização, **S**aturação (filas) e **E**rros. Comece sempre por `uptime` → `top` → `free` → `df` → `ss`.

## 1. CPU, memória e processos

### `uptime` — carga do sistema
- **Sintaxe:** `uptime` · **Exemplo:** `uptime`
- **Resultado:** `14:33:09 up 55 min, 1 user, load average: 4,87, 4,10, 3,60`
- **Interpretar:** os três números são a média de processos prontos para rodar em 1/5/15 min. Compare com `nproc` (12 nesta máquina): load > nº de CPUs = saturação. Se 1 min > 15 min, está piorando.
- **Produção:** primeiro comando ao entrar num servidor lento.

<img width="530" height="33" alt="image" src="https://github.com/user-attachments/assets/af604f9f-fadd-4e3d-a5be-cc59d1759dca" />


### `top` e `htop` — processos em tempo real
- **Sintaxe:** `top` · `top -o %MEM` · `top -p PID` · `htop` (se instalado)
- **Teclas do top:** `P` ordena por CPU, `M` por memória, `1` mostra cada núcleo, `H` threads, `k` mata, `q` sai.
- **Cabeçalho:** `us` user, `sy` kernel, `ni` nice, `id` ocioso, `wa` esperando I/O (disco), `st` roubado por hipervisor. `wa` alto = gargalo de disco, não de CPU.
- **Colunas:** `RES` memória residente real; `S` estado (R rodando, S dormindo, D espera I/O ininterrupta, Z zumbi).
- **Exemplo de problema:** `exercise linux-cpu` → dois processos com ~100 %CPU.

<img width="860" height="962" alt="image" src="https://github.com/user-attachments/assets/2a5b8c8f-4227-41b4-bf25-677bb6209b3a" />
<img width="1652" height="962" alt="image" src="https://github.com/user-attachments/assets/adc19e00-4fa7-4a73-94a9-c162b435e8df" />


### `free` — memória
- **Sintaxe:** `free -h` · **Exemplo:** `free -h`
- **Resultado:** colunas `total used free shared buff/cache available`.
- **Interpretar:** olhe **`available`** (o que dá para usar sem swap), não `free`. Cache de disco (`buff/cache`) é reutilizável. `Swap` cheio + `available` baixo = pressão de memória (risco de OOM killer: `journalctl -k | grep -i oom`).

<img width="683" height="61" alt="image" src="https://github.com/user-attachments/assets/e4f2d15c-7650-474e-97ec-aa93a4c989ca" />


### `ps` — fotografia dos processos
- **Sintaxe:** `ps aux` · `ps -eo pid,ppid,ni,pcpu,pmem,etime,cmd --sort=-pcpu | head`
- **Exemplos:** `ps -fp 1234` (um PID) · `ps -ef --forest` (árvore) · `pgrep -af nome`
- **Interpretar:** `ETIME` mostra há quanto tempo roda (um "processo novo" pode ser reinício em loop).

<img width="504" height="95" alt="image" src="https://github.com/user-attachments/assets/dcc1aa17-89ba-47a0-a2d3-ec9c4feb3dd0" />


### `kill` / `pkill` — sinais
- **Sintaxe:** `kill PID` (SIGTERM, 15: encerrar educadamente) · `kill -9 PID` (SIGKILL: não pode ser ignorado) · `kill -HUP PID` (recarregar config) · `pkill -f padrão`
- **Regra:** sempre SIGTERM primeiro; `-9` não deixa o processo limpar (arquivos temporários, locks). Confirme o PID com `ps -fp` antes.
- **Em containers:** `docker stop` envia SIGTERM e espera 10 s antes do SIGKILL — apps que ignoram SIGTERM demoram a parar.



## 2. Disco

### `df` — espaço por filesystem
- **Sintaxe:** `df -h` · `df -hT /var` · `df -i` (inodes)
- **Interpretar:** `Use%` 100 = cheio. Se `df -h` mostra espaço mas grava falha → `df -i` (inodes esgotados por milhões de arquivos pequenos).

<img width="776" height="53" alt="image" src="https://github.com/user-attachments/assets/b4ca415f-c640-4ea5-b1f8-d8cb4d1bdab0" />
<img width="770" height="51" alt="image" src="https://github.com/user-attachments/assets/f9c9ab33-f8ab-44e9-93da-c1ba7c430d32" />

### `du` — quanto cada diretório ocupa
- **Sintaxe:** `du -sh *` · `du -xh /var --max-depth=1 | sort -h | tail` · `du -ah . | sort -h | tail`
- **Fluxo de "disco cheio":** `df -h` (qual filesystem?) → `du -xh <mount> --max-depth=1 | sort -h` (qual pasta?) → descer até achar o arquivo → `ls -lh`. 🔒 em `/var`.
- **Armadilha:** arquivo apagado mas ainda aberto não libera espaço: `sudo lsof +L1` → reinicie o processo ou trunque (`: > arquivo`).
- **Exercício:** `./lab.sh exercise linux-disk`.

<img width="775" height="143" alt="image" src="https://github.com/user-attachments/assets/3bd6562c-1f83-4bb3-ba47-fb118878c826" />


## 3. Arquivos, busca e logs

### `ls`, `find`, `grep`, `tail`
```bash
ls -lah /var/log                              # tamanhos legíveis, ocultos, permissões
find /var/log -type f -size +50M -mtime -7    # arquivos grandes alterados nos últimos 7 dias
find . -name '*.yaml' -newer Jenkinsfile      # mais novos que um arquivo
grep -rn "ERROR" /var/log/app/ --include='*.log'
grep -E "5[0-9]{2}" access.log | wc -l        # quantos 5xx
tail -f /var/log/syslog                       # acompanha em tempo real (Ctrl-C sai)
tail -n 100 app.log | grep -i timeout
journalctl -u ssh --since "10 min ago"
```
- **Interpretar `ls -l`:** `-rw-r--r-- 1 dono grupo tamanho data nome` (permissões: dono/grupo/outros). "Permission denied" → veja dono, grupo e bits.
- **Pipeline típico de incidente:** `grep ERROR app.log | awk '{print $5}' | sort | uniq -c | sort -rn | head` (erros mais frequentes).

## 4. Serviços: systemctl e journalctl
```bash
systemctl status docker                 # ativo? desde quando? últimas linhas do log
systemctl is-active docker; systemctl is-enabled docker
systemctl list-units --failed           # o que está quebrado
sudo systemctl restart docker           # 🔒
journalctl -u docker -n 50 --no-pager   # últimas 50 linhas do serviço
journalctl -u docker -f                 # seguir
journalctl -p err -b                    # só erros desde o boot
journalctl -k | grep -i -E "oom|killed process"   # OOM killer (kernel)
```
- **Interpretar `status`:** `Active: active (running)` ok · `failed` + `Main PID ... code=exited, status=1/FAILURE` → veja o log logo abaixo · `activating (auto-restart)` = reiniciando em loop (equivalente a CrashLoopBackOff).
- **Produção:** serviço não sobe → `systemctl status X` → `journalctl -u X -xe` → config (`nginx -t`) → porta ocupada (`ss`) → permissão/SELinux/disco.

## 5. Rede

### `ip` — interfaces, endereços e rotas
```bash
ip -br addr          # resumo: interface, estado, IPs
ip route             # tabela de rotas ("default via ..." = gateway)
ip route get 8.8.8.8 # por qual interface/gateway sairia este destino
ip -s link           # contadores de erros/drops por interface
```
- **Interpretar:** sem `default via` = sem saída para fora. `state DOWN` = interface sem link. Erros/drops crescendo = problema físico/driver/MTU.

### `ping` — alcance e latência
`ping -c 4 <host>` · resultado: `64 bytes from ...: time=12.3 ms` e no final `% packet loss` e `rtt min/avg/max/mdev`. Perda > 0 ou `mdev` alto = instabilidade. `ping` bloqueado por firewall não prova queda. Teste primeiro o **IP** (rede) e depois o **nome** (DNS).

### `traceroute` / `mtr` — caminho
`traceroute -n <host>` (instale: `./lab.sh install --apt`) · `mtr -rn -c 10 <host>` (já presente; modo relatório). Cada linha é um salto; `* * *` = não respondeu (pode ser só filtro ICMP). Perda que aparece **a partir de um salto e se mantém até o destino** é real; perda só num salto intermediário costuma ser rate-limit.

### `dig` / `nslookup` — DNS
```bash
dig example.com +short                  # só o IP
dig example.com                         # status (NOERROR/NXDOMAIN/SERVFAIL), ANSWER, query time, SERVER
dig @1.1.1.1 example.com                # consulta um resolvedor específico
dig -x 1.1.1.1 +short                   # reverso
dig example.com MX +short               # tipo de registro
nslookup example.com
```
- **Interpretar:** `NXDOMAIN` = nome não existe · `SERVFAIL` = resolvedor falhou · `timed out; no servers could be reached` = resolvedor inalcançável · `Query time` alto = DNS lento. TTL no ANSWER = por quanto tempo fica em cache.
- **Exercício:** `./lab.sh exercise linux-dns`.

### `ss` e `netstat` — sockets e portas
```bash
ss -ltnp                       # TCP em escuta, numérico, com processo (🔒 para ver processos de outros usuários)
ss -tn state established       # conexões ativas
ss -s                          # resumo (estab, timewait...)
ss -ltn 'sport = :8099'        # filtrar porta
netstat -tulpn                 # equivalente legado (net-tools)
```
- **Interpretar `Local Address:Port`:** `127.0.0.1:5432` aceita só local; `0.0.0.0:80`/`*:80` aceita de qualquer lugar; `[::]` = IPv6. `Recv-Q` crescendo em LISTEN = aplicação não está aceitando conexões (backlog cheio).
- **Exercício:** `./lab.sh exercise linux-port`.

### `curl` e `wget` — HTTP
```bash
curl -s http://127.0.0.1:30080/api/hello                       # corpo
curl -sI http://127.0.0.1:30080/healthz                        # só cabeçalhos
curl -s -o /dev/null -w 'code=%{http_code} total=%{time_total}s connect=%{time_connect}s ttfb=%{time_starttransfer}s\n' http://127.0.0.1:30080/api/work
curl -sv --max-time 5 https://example.com 2>&1 | head -20       # TLS/handshake (-v)
curl -H 'Host: lab.localtest.me' http://127.0.0.1:8080/         # testar Ingress por Host header
wget -qO- http://127.0.0.1:30080/info
```
- **Interpretar `-w`:** `connect` alto = rede/handshake; `ttfb` alto = aplicação lenta; `total` − `ttfb` = transferência. Código 000 = nem conectou. `Connection refused` = nada escutando; `timed out` = filtrado/rota; `Could not resolve host` = DNS.

### `nc` (netcat) — testar porta
```bash
nc -zv 127.0.0.1 30080         # a porta aceita conexão? ("succeeded!")
nc -zv -w 3 host 443           # com timeout
nc -l 9000                     # escutar (terminal 1) e ... echo oi | nc 127.0.0.1 9000 (terminal 2)
```

## 6. Cenários de troubleshooting (do sintoma à causa)
| Sintoma | Sequência de comandos | Causa comum |
|---|---|---|
| Servidor lento | `uptime` → `top` → `free -h` → `df -h` → `iostat`/`top` (`wa`) | CPU saturada, swap, disco cheio/lento |
| Serviço não responde | `systemctl status X` → `journalctl -u X -n 50` → `ss -ltnp` → `curl -v localhost:PORTA` | processo caiu, porta errada, bind em 127.0.0.1 |
| "Connection refused" | `ss -ltn` (alguém escuta?) → firewall (`sudo ufw status`) | serviço parado/porta errada |
| "Timeout" | `ping IP` → `mtr -rn IP` → `nc -zv IP porta` | firewall/Security Group/rota |
| "Could not resolve host" | `cat /etc/resolv.conf` → `dig nome` → `dig @IP-DNS nome` | resolvedor errado/inacessível |
| Disco cheio | `df -h` → `du -xh / --max-depth=1 \| sort -h` → `lsof +L1` | logs sem rotação, arquivo deletado aberto |
| OOM | `journalctl -k \| grep -i oom` → `free -h` → `ps --sort=-rss` | vazamento, limites mal dimensionados |
| Porta ocupada | `ss -ltnp 'sport = :PORTA'` → `ps -fp PID` | instância antiga |

## 7. Relação com Kubernetes e produção
- `kubectl top` = `top` por pod · `kubectl logs` = `tail/journalctl` · `kubectl exec ... -- sh` e use `ss`, `curl`, `nslookup` dentro do pod · eventos do kubelet = `journalctl -u kubelet` (no node; no Kind: `docker exec lab-worker journalctl -u kubelet -n 50`).
- Limites de cgroup (CPU/memória do pod) explicam throttling e OOMKilled: `docker exec lab-worker cat /sys/fs/cgroup/...`.
- Em nuvem: o "firewall" é Security Group (AWS) / NSG (Azure); o "DNS interno" é Route 53 Private Zones / Azure Private DNS (veja [09](09-CLOUD-AWS-AZURE.md)).
