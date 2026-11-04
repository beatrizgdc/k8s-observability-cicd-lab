# Linux: "a internet caiu?" — DNS vs rede

## Objetivo
Separar falha de conectividade (IP) de falha de resolução de nomes.

## Contexto do incidente
"Não consigo acessar nada!" — mas o link está de pé.

## Como reproduzir
`./lab.sh exercise linux-dns` — container com resolvedor inexistente (10.255.255.1).

## Investigação
```bash
ping -c1 <IP do gateway>                  # funciona => rede OK
nslookup example.com                      # falha => DNS
dig example.com +time=2 +tries=1          # detalhes: status, servidor consultado
dig @1.1.1.1 example.com                  # testa outro resolvedor (precisa de internet)
cat /etc/resolv.conf                      # qual nameserver?
resolvectl status                         # no host com systemd-resolved
ip route                                  # rota padrão (ip route get 8.8.8.8)
```
**Como interpretar:** ping por IP OK + nome falha = DNS. `connection timed out; no servers could be reached` = resolvedor inacessível. `NXDOMAIN` = o nome não existe (resolvedor ok). `SERVFAIL` = o resolvedor falhou ao resolver.

## Causa-raiz
`/etc/resolv.conf` apontando para um servidor DNS inexistente.

## Como resolver
`./lab.sh exercise linux-dns fix` (recria o container com o DNS padrão). No host: corrigir `resolvectl dns <iface> <ip>` / DHCP.

## Como validar
`./lab.sh exercise linux-dns validate` (requer internet nesta etapa).

## Limpeza / Perguntas
`./lab.sh exercise linux-dns reset`. Perguntas: como o `traceroute`/`mtr` ajuda? Qual a ordem de resolução (`/etc/nsswitch.conf`, `/etc/hosts`)? TTL e cache?
