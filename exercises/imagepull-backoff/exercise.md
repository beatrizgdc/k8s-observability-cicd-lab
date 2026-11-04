# ImagePullBackOff (tag de imagem errada)

## Objetivo
Reconhecer ErrImagePull/ImagePullBackOff e achar a causa em `describe`/Events.

## Contexto do incidente
Novo deploy do `checkout` nunca sobe; o pod mostra `ImagePullBackOff`.

## Como reproduzir
`./lab.sh exercise imagepull-backoff`

## Investigação
```bash
NS=inc-imagepull-backoff
kubectl -n $NS get pods                                      # ErrImagePull -> ImagePullBackOff
kubectl -n $NS describe pod -l app=checkout | tail -15       # Events: Failed to pull image "lab-app:1.0.O" ... not found / pull access denied
kubectl -n $NS get deploy checkout -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```
**Como interpretar:** a mensagem de Events diz *por que*: tag inexistente, repositório privado sem `imagePullSecrets` (`unauthorized`), registry inacessível (timeout), arquitetura errada. Aqui: a tag tem a letra **O** em vez de **0**.

## Causa-raiz
Erro de digitação na tag da imagem.

## Como resolver
`./lab.sh exercise imagepull-backoff fix` (= `kubectl set image deploy/checkout app=lab-app:1.0.0`)

## Como validar
`./lab.sh exercise imagepull-backoff validate` → pod Running.

## Limpeza
`./lab.sh exercise imagepull-backoff reset`

## Modelo de RCA (resumo)
Causa: tag errada. Prevenção: pipeline que gera a tag (não digitar), verificação de existência da imagem antes do deploy, tags imutáveis/digest.

## Perguntas de revisão
1. ErrImagePull vs ImagePullBackOff? 2. Como puxar de ECR/ACR privado? (imagePullSecrets, IAM/managed identity.)
3. Por que evitar `latest`? 4. `imagePullPolicy` Always/IfNotPresent/Never?
