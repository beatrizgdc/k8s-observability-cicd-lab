# Problema de resolução DNS

## Objetivo
Separar "rede quebrada" de "DNS quebrado" dentro do cluster e entender o CoreDNS/`resolv.conf` dos pods.

## Contexto do incidente
Um pod não resolve nenhum nome (`nslookup` dá timeout) enquanto outros pods do mesmo namespace funcionam.

## Como reproduzir
```bash
./lab.sh exercise dns-failure
```
Cria `client-ok` (DNS padrão) e `client-broken` (`dnsPolicy: None` apontando para 10.255.255.1, que não existe).

## Investigação
```bash
NS=inc-dns-failure
kubectl -n $NS exec client-ok -- nslookup alvo.$NS.svc.cluster.local        # funciona
kubectl -n $NS exec client-broken -- nslookup -timeout=3 alvo.$NS.svc.cluster.local   # "no servers could be reached"
kubectl -n $NS exec client-ok -- cat /etc/resolv.conf       # nameserver 10.96.0.10 (kube-dns) + search ...svc.cluster.local
kubectl -n $NS exec client-broken -- cat /etc/resolv.conf   # nameserver 10.255.255.1
kubectl -n kube-system get pods -l k8s-app=kube-dns         # CoreDNS saudável?
kubectl -n kube-system get svc kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
kubectl -n $NS get pod client-broken -o jsonpath='{.spec.dnsPolicy}{"\n"}'
```
**Como interpretar:** CoreDNS saudável + `client-ok` resolvendo ⇒ problema local do pod. O `resolv.conf` do pod quebrado aponta para outro servidor.

## Causa-raiz
`dnsPolicy: None` com `dnsConfig` apontando para um nameserver inexistente.

## Como resolver
```bash
./lab.sh exercise dns-failure fix     # recria o pod com a política padrão ClusterFirst
```
(`dnsPolicy` não pode ser alterado em pod existente; recria-se o pod/Deployment.)

## Como validar
`./lab.sh exercise dns-failure validate` → `nslookup` retorna o ClusterIP do Service.

## Limpeza
`./lab.sh exercise dns-failure reset`

## Modelo de RCA (resumo)
Causa: configuração de DNS customizada incorreta. Prevenção: não sobrescrever dnsPolicy sem necessidade; teste de DNS no smoke test.

## Perguntas de entrevista
1. Qual o FQDN de um Service? (`<svc>.<ns>.svc.cluster.local`.)
2. O que o `ndots:5` provoca? (várias consultas com search domains antes do nome absoluto → latência.)
3. Se o CoreDNS caísse, o que falharia? (descoberta por nome; IPs diretos continuam.)
4. Como depurar com um pod efêmero? (`kubectl run -it --rm dbg --image=busybox:1.37 -- sh`.)
