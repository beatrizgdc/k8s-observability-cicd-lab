# Pod em CrashLoopBackOff (variável de ambiente ausente)

## Objetivo
Aprender o fluxo `get → describe → logs --previous` para pods que reiniciam em loop.

## Contexto do incidente
Após um deploy, o `orders-api` nunca fica Ready. O time diz: "funcionava no ambiente de testes". O pod está em `CrashLoopBackOff`.

## Como reproduzir
```bash
./lab.sh exercise kubernetes-crashloop
```
Cria o namespace `inc-kubernetes-crashloop` com um Deployment que exige a variável `DATABASE_URL` (que não é definida).

## Investigação
```bash
NS=inc-kubernetes-crashloop
kubectl -n $NS get pods                                  # STATUS CrashLoopBackOff/Error, RESTARTS subindo
kubectl -n $NS describe pod -l app=orders-api            # veja "Last State", "Exit Code" e a seção Events
kubectl -n $NS logs deploy/orders-api --previous         # log da execução ANTERIOR (a que morreu)
kubectl -n $NS get events --sort-by=.lastTimestamp | tail
```
**Como interpretar**
- `Exit Code: 3` com `Reason: Error` = o processo saiu por conta própria (não foi OOM nem kill). Código 137 seria SIGKILL/OOM; 1/2/3 geralmente é erro da aplicação.
- `logs --previous` mostra: `variável obrigatória DATABASE_URL ausente; encerrando`.
- O backoff cresce (10s, 20s, 40s… até 5 min): por isso "CrashLoop" parece demorar.

## Causa-raiz
Configuração ausente: o Deployment não injeta `DATABASE_URL`. Não é problema de imagem, rede nem recurso.

## Como resolver
```bash
./lab.sh exercise kubernetes-crashloop fix
# equivalente a:
kubectl -n inc-kubernetes-crashloop set env deploy/orders-api DATABASE_URL=postgres://db.exemplo:5432/orders
```
Em produção, o valor viria de um Secret/ConfigMap (`envFrom`), não de um valor literal.

## Como validar
```bash
./lab.sh exercise kubernetes-crashloop validate     # rollout concluído, pod 1/1 Running
kubectl -n inc-kubernetes-crashloop get pods
```

## Limpeza
```bash
./lab.sh exercise kubernetes-crashloop reset
```

## Modelo de RCA (resumo)
- **Impacto:** serviço indisponível desde o deploy X. **Detecção:** alerta de pods não Ready.
- **Causa:** variável DATABASE_URL não incluída no manifesto do deploy. **Correção:** adicionada. **Prevenção:** validação de config no CI, `kubectl diff`, checklist de variáveis obrigatórias.

## Perguntas de revisão
1. Qual a diferença entre `CrashLoopBackOff` e `Error`? (Error = última saída; CrashLoopBackOff = o kubelet está esperando o backoff antes de reiniciar.)
2. Por que usar `--previous`? E se o container nunca chegou a iniciar? (Veja `describe` → Events.)
3. Cite 4 causas de CrashLoopBackOff. (config ausente, comando errado, OOM, liveness probe falhando, dependência indisponível.)
4. Como saber se foi OOM? (`Reason: OOMKilled`, exit 137.)
