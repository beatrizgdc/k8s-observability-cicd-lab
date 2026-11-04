# 05 — Jenkins e CI/CD

## 1. Conceitos
- **CI (Integração Contínua):** a cada commit, build + testes + análises automáticas → feedback rápido. **CD:** *Delivery* = sempre pronto para publicar (aprovação manual); *Deployment* = publica automaticamente em produção.
- **Pipeline:** sequência automatizada de **stages** (etapas) com **steps** (comandos). **Job:** definição executável no Jenkins (aqui, um *Pipeline job* chamado `lab-app`). **Build:** uma execução do job (#1, #2…).
- **Controller × Agent:** o controller agenda e mostra; os *agents/executors* executam. No lab há um único nó (o próprio controller, 2 executors). Em produção: agents efêmeros (containers/pods K8s).
- **Jenkinsfile:** a pipeline como código, versionada com a aplicação (*pipeline as code*). Declarative (`pipeline { ... }`, usado aqui) × Scripted (Groovy livre).
- **Webhook (conceitual):** o Git (GitHub/Azure DevOps) chama uma URL do Jenkins a cada push/PR e dispara o build, sem polling. Aqui não há Git remoto: o Jenkins faz checkout de um repositório local e o build é manual (`./lab.sh pipeline run`). Em produção você configuraria o trigger `githubPush()`/webhook.
- **Rollback:** voltar à versão anterior — `kubectl rollout undo`, redeploy da tag anterior ou *revert* no Git (preferível: rastreável).

## 2. Como o lab foi montado
```
./lab.sh start cicd
 ├─ cria .data/app-repo  (repo git local com app + Jenkinsfile; é o "GitHub" do lab)
 ├─ Jenkins em Docker (cicd/jenkins/Dockerfile): + docker CLI, kubectl, kind, trivy, sonar-scanner, python3
 ├─ Configuration as Code (casc.yaml): usuário admin/admin e o job "lab-app" já criado
 └─ montagens: docker.sock (builds usam o Docker do host), kubeconfig interno do Kind, cache do Trivy
```
Acesse http://127.0.0.1:8088 (admin / admin). Job **lab-app** → *Build with Parameters*/*Build Now*, ou:
```bash
./lab.sh pipeline run                          # dispara e mostra o log no terminal
./lab.sh pipeline run DEPLOY=false             # parâmetro: não faz deploy
./lab.sh pipeline run TRIVY_FAIL_ON=HIGH,CRITICAL   # security scan mais rígido
```
(Parâmetros só existem a partir do 2º build, depois que o Jenkins lê o Jenkinsfile.)

## 3. A pipeline, estágio por estágio ([app/Jenkinsfile](../app/Jenkinsfile))
| # | Stage | O que faz | Como interpretar / falhas típicas |
|---|---|---|---|
| 1 | **Checkout** | `checkout scm` do repo; mostra o último commit | falha: repo inacessível/credencial. Confirme o commit que está sendo construído |
| 2 | **Build** | cria venv, `pip install -r requirements-dev.txt`, `py_compile app.py` | falha: dependência inexistente/versão quebrada, erro de sintaxe, sem acesso ao PyPI no 1º build |
| 3 | **Test** | `pytest --junitxml --cov` e publica resultados JUnit | falha: teste quebrado → aba *Test Result*; veja o assert. Mostra cobertura |
| 4 | **Code Quality** | `flake8` (lint) + `sonar-scanner` com Quality Gate *se* SonarQube estiver no ar e configurado; senão avisa e pula | falha: erro de lint (E/F…) ou *Quality Gate FAILED* |
| 5 | **Security Scan** | `trivy fs` sobre dependências e Dockerfile; reprova por severidade (`TRIVY_FAIL_ON`, padrão CRITICAL, só com correção disponível) | falha: CVE crítica em dependência/misconfig → atualizar a lib |
| 6 | **Docker Build** | `docker build -t lab-app:jenkins-N` + `trivy image` | falha: erro no Dockerfile; CVE crítica na imagem/base |
| 7 | **Deploy Kubernetes** | `kind load docker-image`, `kubectl set image`, `rollout status`, smoke test `curl /info`; **em falha → `rollout undo`** automático | falha: rollout não conclui (probe, imagem); smoke test falhou |
Resultado esperado de um build verde (observado neste lab, build #3): todos os estágios verdes e `/info` retornando `"version":"1.0.3"` (versão = `1.0.<nº do build>`).
Veja o efeito no cluster: `kubectl --context kind-lab -n demo get pods -o wide` e `kubectl -n demo rollout history deploy/lab-app`.

**Habilitar o estágio Sonar de verdade:**
```bash
./lab.sh start security      # espere ~2-3 min
./lab.sh sonar-setup         # troca a senha inicial, gera token (.data/secrets/sonar-token)
./lab.sh pipeline run        # agora "Code Quality" executa o sonar-scanner e espera o Quality Gate
```
Resultado: `QUALITY GATE STATUS: PASSED` e o projeto `lab-app` em http://127.0.0.1:9000.
RAM: Jenkins (~1,2 GB) + SonarQube (~2,5 GB) + k8s juntos exigem ~6 GB livres; pare observability se precisar.

## 4. Lendo o Console Output
- Cada `[Pipeline] { (Nome do stage) }` marca o início de um estágio; `+ comando` = o `sh` executado; linhas sem prefixo = saída do comando.
- A **primeira** linha com `ERROR`/`FAILED`/`Exception` costuma ser a causa; o resto é consequência. `script returned exit code N` apenas diz que o comando falhou.
- *Stage View* (barra de estágios) → o estágio vermelho; clique em *Logs*. *Test Result* → testes. Linha do tempo no final: `Finished: FAILURE`.
- Pelo terminal: `./lab.sh pipeline run | grep -nE "ERROR|FAILED|Finished"`.

## 5. Exemplos de falhas e como investigar
| Falha | Como provocar | Onde aparece | Correção |
|---|---|---|---|
| Teste quebrado | `./lab.sh exercise jenkins-pipeline-fail` | stage **Test**: `FAILED tests/test_app.py::test_hello` | `git revert` ou ajustar o teste |
| Lint | adicione `import os` não usado em `.data/app-repo/app.py` e faça commit | **Code Quality**: `F401 'os' imported but unused` | remover import |
| CVE crítica | em `.data/app-repo/requirements.txt` troque para `pyyaml==5.3` e commit | **Security Scan**: `CVE-2020-14343 CRITICAL` + exit code 1 | atualizar versão; ou `TRIVY_FAIL_ON=NONE` só para relatório |
| Docker Build | quebre a 1ª linha do Dockerfile (`FROM python:9.99`) | **Docker Build**: `manifest unknown / not found` | corrigir a tag da base |
| Deploy/rollout | no Jenkinsfile de `.data/app-repo`, no stage Deploy, acrescente `kubectl -n demo set env deployment/lab-app FAIL_HEALTH=1` antes do `rollout status` (pods novos ficam NotReady) | **Deploy**: `rollout status` estoura (timeout 120s) e o `post failure` executa `rollout undo` (volta **uma** revisão: confira `rollout history` e, se preciso, `rollout undo --to-revision=N`) | remover a causa; `./lab.sh reset` restaura o `demo` |
| Falta de recurso | pare o Docker/SonarQube; pouca RAM | `Cannot connect to the Docker daemon` / `OOMKilled` do Jenkins | `docker ps`, `./lab.sh status`, libere memória |
Para qualquer falha: `git -C .data/app-repo log --oneline` (o que mudou), `docker logs lab-jenkins` (problemas do próprio Jenkins), `docker exec lab-jenkins sh -c 'kubectl get nodes'` (acesso ao cluster).

## 6. Boas práticas e segurança
- Pipeline como código; stages pequenos e idempotentes; `timeout`, `disableConcurrentBuilds`, `buildDiscarder` (já no Jenkinsfile).
- Segredos: *Credentials* do Jenkins (`withCredentials`), nunca no repositório; `set +x` ao manipular tokens (veja o stage Sonar).
- Agents efêmeros; mínimo privilégio. **Neste lab o docker.sock é montado — equivale a root no host; não replique em produção** (use Kaniko/BuildKit rootless, agents isolados).
- Falhar rápido: lint/teste antes de build de imagem; scan antes de publicar; promover o **mesmo artefato** entre ambientes.
- Deploy com verificação (`rollout status`, smoke test) e rollback automático; deploys por GitOps (Argo CD/Flux) como evolução.

## 7. Perguntas de revisão
1. Como o Jenkins escala? (agents efêmeros, Kubernetes plugin.) 2. Declarative × Scripted?
3. Como fazer rollback automático? (post failure + `rollout undo`, ou promoção reversa/Git revert.) 4. Como evitar vazar segredos?
5. Pipeline lenta: o que otimiza? (cache de dependências/camadas, paralelismo `parallel`, agents maiores.) 6. Webhook × polling? 7. Diferença entre Jenkins e GitHub Actions/Azure DevOps Pipelines?
