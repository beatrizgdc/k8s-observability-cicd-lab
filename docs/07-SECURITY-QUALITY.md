# 07 — Qualidade de código e segurança

Ferramentas locais do lab: **SonarQube Community Build** (SAST/qualidade) e **Trivy** (SCA + imagens + IaC + segredos). **SonarCloud** e **Snyk** exigem conta e **não** são executados: abaixo estão a comparação e como a integração funcionaria.

> Todos os resultados mostrados nesta página foram obtidos executando as ferramentas reais neste lab (SonarQube 26.10 Community, Trivy 0.76.1 com banco local). O código em `security/samples/vulnerable-app/` é **inseguro de propósito**. Os números mudam com o tempo (banco de CVEs).

## 1. Conceitos
| Sigla | Significado | Analisa | Ferramenta típica | Quando |
|---|---|---|---|---|
| **SAST** | Static Application Security Testing | seu código-fonte (sem executar) | SonarQube, Snyk Code | commit/PR |
| **SCA** | Software Composition Analysis | dependências (`requirements.txt`, `package.json`) × CVEs | Trivy, Snyk Open Source, Dependabot | commit/build |
| **Container scan** | pacotes do SO e libs dentro da imagem | imagem Docker | Trivy, Snyk Container | após `docker build` |
| **IaC scan** | Terraform/K8s/Dockerfile mal configurados | arquivos de infra | Trivy config, Checkov | PR |
| **Secrets scan** | chaves/senhas no código | repositório | Trivy secret, gitleaks | commit |
| **DAST** | testa a app em execução | HTTP | OWASP ZAP | ambiente de teste |
**Termos do Sonar:** *Bug* (erro provável de execução), *Vulnerability* (falha explorável), *Security Hotspot* (ponto sensível a revisar), *Code Smell* (manutenibilidade), *Coverage*, *Duplications*, **Quality Gate** (conjunto de condições de aprovação), *New Code* (foco em código novo — “clean as you code”).
**Termos de CVE:** CVE (identificador), CVSS (nota 0–10), severidade LOW/MEDIUM/HIGH/CRITICAL, *Fixed Version* (versão corrigida). Severidade ≠ risco: depende de exposição e explorabilidade.

## 2. SonarQube Community Build (local)
```bash
./lab.sh start security       # ~2-3 min; http://127.0.0.1:9000
./lab.sh sonar-setup          # troca a senha inicial (admin / Lab-Admin-2026!) e gera token em .data/secrets/sonar-token
./lab.sh install sonar-scanner   # scanner no host (uma vez)
./lab.sh scan sonar-sample    # analisa security/samples/vulnerable-app com o gate "Lab strict"
```
Resultado real da análise do exemplo (`vulnerable-sample`): **5 Vulnerabilities, 1 Bug** (de um arquivo pequeno), por exemplo:
- `python:S4790` (CRITICAL) hash fraco (MD5) · `python:S4502` (CRITICAL) CSRF desabilitado · `python:S8392` (BLOCKER) bind em todas as interfaces · `python:S4507` debug ativado · `docker:S6471` imagem rodando como root · Bug `python:S930` chamada com argumento faltando (`yaml.load`).
- Abra http://127.0.0.1:9000/dashboard?id=vulnerable-sample → *Issues* → clique numa issue: “Why is this an issue?” + exemplo de correção; *Security Hotspots* para revisão.
**Quality Gate:** o padrão *Sonar way* avalia **código novo** (sem vulnerabilidades novas, cobertura ≥ 80%, duplicação ≤ 3%). Para ver uma reprovação o lab cria o gate **“Lab strict”** (reprova com QUALQUER vulnerabilidade) e a análise termina com `QUALITY GATE STATUS: FAILED` (observado). Já o `lab-app` (a pipeline) passou: `QUALITY GATE STATUS: PASSED`.
Para treinar “fechar o gate”: corrija as issues em `security/samples/vulnerable-app/app.py` e rode `./lab.sh scan sonar-sample` de novo — ele passa a aprovar.

**Integração com CI/CD:** no Jenkinsfile o estágio *Code Quality* executa `sonar-scanner -Dsonar.qualitygate.wait=true`; se o gate falhar, o build falha antes do Docker Build/Deploy (o mesmo vale para Azure DevOps/GitHub Actions). Configuração do projeto: [app/sonar-project.properties](../app/sonar-project.properties) (`sonar.sources`, `sonar.tests`, cobertura `coverage.xml`).
Limitações desta edição *Community*: sem análise de branches/PR (isso é Developer Edition+), um banco H2 embutido só para avaliação (para uso real: PostgreSQL), análise de menos linguagens que as edições pagas.

## 3. SonarQube × SonarCloud
| | SonarQube (self-hosted) | SonarCloud (SaaS da Sonar) |
|---|---|---|
| Onde roda | seu servidor/container | nuvem da Sonar |
| Operação | você mantém (atualização, banco, backup) | zero manutenção |
| Integração Git | configuração manual | App nativo GitHub/GitLab/Bitbucket/Azure DevOps, **decoração de PR** |
| Branch/PR analysis | só nas edições pagas | incluído (projetos públicos grátis; privados pagos) |
| Dados | ficam na sua rede | código analisado sobe para o SaaS |
| Autenticação | local/LDAP/SSO | conta Sonar/Git provider |
**Como é a análise em pipeline (conceitual, não executado):** o scanner roda no CI e envia o resultado ao servidor; a diferença está nos parâmetros:
```bash
# SonarQube (o que o lab faz)
sonar-scanner -Dsonar.host.url=http://lab-sonarqube:9000 -Dsonar.token=$SONAR_TOKEN -Dsonar.projectKey=lab-app
# SonarCloud (exigiria conta e token externo — NÃO executado)
sonar-scanner -Dsonar.host.url=https://sonarcloud.io -Dsonar.organization=<org> -Dsonar.token=$SONAR_TOKEN -Dsonar.projectKey=<org>_lab-app
```
Nota: o produto atual da Sonar na nuvem chama-se **SonarQube Cloud** (antes SonarCloud) — o conceito é o mesmo.

## 4. Trivy (local) — SCA, imagem, IaC, segredos
O banco de vulnerabilidades é baixado uma vez (`./lab.sh install`) e os scans usam `--skip-db-update` (offline). Alvos:
```bash
./lab.sh scan fs app                        # dependências do app + misconfig + secrets
./lab.sh scan sample                        # o exemplo inseguro (dependências, Dockerfile, segredo)
./lab.sh scan image lab-app:1.0.0           # imagem do app (OS + libs)
./lab.sh exercise vulnerable-image          # build + scan de imagem insegura; fix compara antes × depois
trivy image --skip-db-update --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 lab-app:1.0.0   # modo "gate" de CI
trivy image --skip-db-update --format json -q lab-vuln:demo | jq '[.Results[].Vulnerabilities[]?]|group_by(.Severity)|map({(.[0].Severity):length})|add'
```
**Resultados reais neste lab:** `scan sample` → 17 achados em dependências (2 CRITICAL, 5 HIGH — ex.: `pyyaml 5.3` `CVE-2020-14343` CRITICAL, corrigido em 5.4; `flask 0.12.2` `CVE-2018-1000656` HIGH → 0.12.3; `requests 2.19.1` `CVE-2018-18074`; `jinja2 2.10` `CVE-2019-10906`) + Dockerfile: `DS-0031` CRITICAL (senha em `ENV`), `DS-0002` HIGH (root), `DS-0026` LOW (sem HEALTHCHECK). Imagem `lab-vuln:demo`: **4 CRITICAL, 55 HIGH, 79 MEDIUM, 32 LOW**; após o fix (`lab-vuln:fixed`): **0 CRITICAL, 45 HIGH** (os HIGH restantes são pacotes Debian sem correção publicada).
**Ler a tabela:** `Library | Vulnerability | Severity | Status | Installed Version | Fixed Version | Title`. `Status: fixed` → há versão corrigida; `affected`/`will_not_fix` → sem correção (decida: mitigar/aceitar/trocar base). Boas práticas: base mínima (`slim`/`distroless`), atualizar com frequência, lockfile, rodar no CI e *também* periodicamente (novas CVEs surgem depois do deploy).

## 5. Snyk (conceitual — exige conta, não executado)
| Produto | Equivale a | Entrada | Ex. de comando (com conta/token) |
|---|---|---|---|
| **Snyk Open Source** | SCA | manifests/lockfiles | `snyk test` |
| **Snyk Code** | SAST | código-fonte | `snyk code test` |
| **Snyk Container** | scan de imagem | imagem + Dockerfile | `snyk container test lab-app:1.0.0` |
| **Snyk IaC** | scan de Terraform/K8s | `.tf`/YAML | `snyk iac test` |
`snyk auth` abre o navegador/token (por isso não há como rodá-lo sem cadastro). Diferenciais frente a ferramentas OSS: base de vulnerabilidades curada com dados de explorabilidade e *reachability*, **PRs automáticos de correção** (Fix PRs), priorização por *Snyk Priority Score*, IDE plugins, painel central por organização.

### Snyk × Trivy
| | Trivy | Snyk |
|---|---|---|
| Licença/custo | open source (Apache-2.0), grátis | SaaS comercial (plano grátis limitado) |
| Conta | não precisa | **precisa** (`snyk auth`) |
| Execução | 100% local/offline após baixar o DB | consulta a API da Snyk |
| Escopo | SCA, imagem, IaC, secrets, SBOM, K8s | idem + **SAST (Snyk Code)** e gestão central |
| Base de dados | NVD + avisos de distros/GitHub | base proprietária própria (muitas vezes antecipa/enriquece NVD) |
| Correção | informa versão corrigida | sugere upgrades e abre PRs |
| Melhor para | gate de CI simples, offline, sem custo | governança em escala, priorização e remediação assistida |
No pipeline: `trivy image --exit-code 1 --severity CRITICAL IMG` ↔ `snyk container test IMG --severity-threshold=high`.

## 6. Onde cada ferramenta entra no pipeline
```
commit ─► [secrets scan] ─► build ─► testes ─► [SAST: Sonar/Snyk Code] ─► [SCA: Trivy/Snyk OS]
        ─► docker build ─► [container scan: Trivy/Snyk Container] ─► deploy ─► [DAST/monitoramento]
```
No lab: Jenkins executa lint + Sonar (se ligado) + `trivy fs` + `trivy image` antes do deploy, com `TRIVY_FAIL_ON` controlando o gate.

## 7. Perguntas de entrevista
1. SAST × SCA × DAST? 2. O que é um Quality Gate e o que fazer quando bloqueia o release? 3. “Shift left” — o que significa na prática?
4. A CVE crítica não tem correção: o que fazer? (mitigar, WAF/config, remover componente, aceitar com prazo.) 5. Falso positivo: como tratar? (marcar como *Won’t fix/False positive* com justificativa, `.trivyignore`.)
6. Por que scan de imagem *depois* de aprovado ainda importa? (CVEs novas; rebuilds agendados.) 7. SBOM: o que é e para que serve?
