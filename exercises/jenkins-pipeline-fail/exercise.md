# Pipeline Jenkins com falha

## Objetivo
Ler o Console Output do Jenkins, achar o estágio que falhou e ligar a falha ao commit responsável.

## Contexto do incidente
O último commit ("internacionaliza mensagem") fez a pipeline `lab-app` ficar vermelha. Nada foi implantado.

## Como reproduzir
```bash
./lab.sh start cicd            # Jenkins em http://127.0.0.1:8088 (admin/admin)
./lab.sh exercise jenkins-pipeline-fail
```
O script faz um commit no repositório local `.data/app-repo` (o que o Jenkins faz checkout) e dispara a pipeline.

## Investigação
- Jenkins → job `lab-app` → build vermelho → **Stage View**: o estágio `Test` está vermelho; os seguintes estão "cinza" (não executaram).
- **Console Output**: procure `FAILED` / `AssertionError`:
  `FAILED tests/test_app.py::test_hello ... 1 failed, 10 passed`
- **Test Result** (plugin JUnit) mostra o teste e o stack trace.
```bash
git -C .data/app-repo log --oneline -3          # qual commit?
git -C .data/app-repo show HEAD                 # o que mudou (olá do lab -> hello from lab)
./lab.sh pipeline run                           # reexecuta e mostra o log no terminal
```
**Como interpretar:** Checkout/Build OK ⇒ ambiente e dependências bem; falha em Test ⇒ regressão de código. Pipeline parou antes de Docker Build/Deploy: nada ruim chegou ao cluster (o objetivo do CI).

## Causa-raiz
Mudança na mensagem sem atualizar o teste que a valida.

## Como resolver
```bash
./lab.sh exercise jenkins-pipeline-fail fix       # git revert do commit ruim
./lab.sh exercise jenkins-pipeline-fail validate  # roda a pipeline: SUCCESS
```
(Alternativa: corrigir o teste e commitar.)

## Outras falhas para provocar (veja docs/05-JENKINS-CICD.md)
`flake8` (estilo), Security Scan (`TRIVY_FAIL_ON`), Docker Build (Dockerfile quebrado), Deploy (imagem inexistente → rollback automático).

## Limpeza
`./lab.sh exercise jenkins-pipeline-fail reset` (reverte o commit se ainda estiver lá).

## Modelo de RCA (resumo)
Causa: commit sem teste correspondente. Detecção: CI. Prevenção: rodar testes localmente/pre-commit, PR obrigatório com CI verde.

## Perguntas de revisão
1. Diferença entre CI e CD? Onde o rollback entra?
2. Como investigar uma pipeline que "funcionava ontem"? (diff de commits, versões de dependências, estado do agente/cache.)
3. Declarative vs Scripted pipeline?
4. Como evitar que segredos apareçam no log? (credentials binding, `set +x`.)
