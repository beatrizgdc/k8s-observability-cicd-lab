# Imagem Docker com vulnerabilidades

## Objetivo
Executar scan de imagem e de dependências com Trivy, ler severidades/CVEs e corrigir atualizando base e libs.

> O código e o Dockerfile em `security/samples/vulnerable-app/` são **inseguros de propósito**. Os resultados abaixo vêm do Trivy real (banco local), não são simulados.

## Contexto do incidente
O time de segurança reprova a imagem `lab-vuln:demo` no gate de release: "há CVEs CRITICAL".

## Como reproduzir
```bash
./lab.sh exercise vulnerable-image
```
Executado neste lab: **4 CRITICAL, 55 HIGH, 79 MEDIUM, 32 LOW** (+3 UNKNOWN) na imagem `python:3.8-slim-buster` + dependências antigas. (Os números mudam com o tempo conforme o banco de CVEs é atualizado.)

## Investigação
```bash
./lab.sh scan image lab-vuln:demo                                   # tabela completa
trivy image --skip-db-update --severity CRITICAL lab-vuln:demo      # só críticas
./lab.sh scan sample                                                # SCA do requirements.txt + secrets + Dockerfile (misconfig)
```
Exemplos de achados reais no `scan sample`: `pyyaml 5.3` — `CVE-2020-14343` (CRITICAL, corrigido em 5.4); `flask 0.12.2` — `CVE-2018-1000656` (HIGH, 0.12.3); `requests 2.19.1` — `CVE-2018-18074`; Dockerfile `DS-0031` (CRITICAL): segredo exposto em `ENV DB_PASSWORD`; `DS-0002`: roda como root.

**Como interpretar:** colunas *Library, Vulnerability, Severity, Installed, Fixed Version*. Se há *Fixed Version*, atualizar resolve. Sem correção disponível (`--ignore-unfixed` esconde) = aceitar risco/mitigar. Separe vulnerabilidades do **SO base** (trocar/atualizar imagem) das **dependências da app** (atualizar libs).

## Causa-raiz
Imagem base antiga (EOL) + dependências com CVEs conhecidos + segredo no Dockerfile + root.

## Como resolver
```bash
./lab.sh exercise vulnerable-image fix     # constrói lab-vuln:fixed (python:3.12-slim, libs atuais, USER não-root) e compara
```

## Como validar
```bash
./lab.sh exercise vulnerable-image validate    # 0 CRITICAL em lab-vuln:fixed
```
Resultado real neste lab: CRITICAL 4 → 0; HIGH 55 → 45 (restam pacotes do Debian sem correção disponível — é normal: gate por severidade + `--ignore-unfixed` + prazo para o resto).

## Limpeza
`./lab.sh exercise vulnerable-image reset`

## Modelo de RCA (resumo)
Causa: base e libs sem atualização. Prevenção: scan no CI (Trivy/Snyk Container), Renovate/Dependabot, imagens mínimas (slim/distroless), rebuild periódico.

## Perguntas de revisão
1. SAST vs SCA vs container scan? 2. O que é CVSS e por que severidade ≠ risco real (exploitability, exposição)?
3. Como tratar uma CVE sem correção? 4. Por que não colocar segredo em `ENV`/camadas da imagem?
