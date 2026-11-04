# 04 — Terraform e Infrastructure as Code

Wrapper do lab: `./lab.sh tf <01|02> <comando terraform>` (equivale a `terraform -chdir=terraform/0X-... <comando>` com cache de providers em `.data/tf-plugin-cache`). O **primeiro** `init` baixa providers de registry.terraform.io (precisa de internet 1 vez); depois funciona offline. Nada é criado em nuvem.

## 1. Conceitos
- **IaC:** infraestrutura descrita em arquivos versionados (Git), revisável (PR), repetível e auditável. Terraform é **declarativo**: você descreve o estado desejado; ele calcula o *plano* (diff) e aplica.
- **Provider:** plugin que fala com uma API (AWS, Azure `azurerm`, Kubernetes, local, random...). Declarado em `required_providers`.
- **Resource:** objeto gerenciado (`resource "tipo" "nome" {...}`) — ex.: `kubernetes_deployment.web`, `local_file.config`; na nuvem: `aws_instance`, `azurerm_kubernetes_cluster`.
- **Data source:** lê algo existente (`data "..."`), sem criar.
- **Variable / Output:** entradas (`variable`) e saídas (`output`) do módulo. Valores via `-var`, `*.tfvars`, `TF_VAR_nome`.
- **State:** arquivo (`terraform.tfstate`) que mapeia recursos do código ↔ objetos reais. Sem ele o Terraform não sabe o que já criou. **Contém segredos** → nunca no Git; em equipe use *remote state* (S3+DynamoDB lock, Azure Storage Blob com lease) com lock e criptografia.
- **Dependências:** implícitas (uma referência como `kubernetes_namespace.this.metadata[0].name` cria a ordem) e explícitas (`depends_on`). O grafo permite criar em paralelo o que é independente (`terraform graph`).
- **Drift:** alguém alterou o real fora do Terraform; `plan` detecta (refresh) e propõe voltar ao código.
- **Módulos:** pacotes reutilizáveis de recursos.

## 2. Ciclo de trabalho
| Comando | Finalidade | Resultado esperado |
|---|---|---|
| `terraform init` | baixa providers/módulos, inicializa backend | `Terraform has been successfully initialized!` e cria `.terraform/` + `.terraform.lock.hcl` (versões fixadas — versione este arquivo) |
| `terraform fmt -recursive` | padroniza formatação | lista arquivos alterados |
| `terraform validate` | valida sintaxe/referências (sem acessar a API) | `Success! The configuration is valid.` |
| `terraform plan [-out=tfplan]` | mostra o que mudará | símbolos `+` criar, `~` alterar, `-` destruir, `-/+` recriar; resumo `Plan: X to add, Y to change, Z to destroy` |
| `terraform apply [tfplan]` | executa o plano (pede `yes`) | `Apply complete! Resources: X added...` + Outputs |
| `terraform output [-json]` | mostra saídas | valores |
| `terraform state list / show <rec>` | inspeciona o state | lista de recursos |
| `terraform destroy` | remove tudo que o state gerencia | `Destroy complete!` |
| `terraform import` / `state rm` / `taint → -replace` | adotar recurso existente / esquecer / forçar recriação | |

## 3. Exercício 1 — conceitos sem cluster (`terraform/01-local-basics`)
Cria um valor aleatório (`random_pet`) e um arquivo (`local_file`) que depende dele; tem variáveis com validação e outputs.
```bash
./lab.sh tf 01 init
./lab.sh tf 01 fmt -check
./lab.sh tf 01 validate
./lab.sh tf 01 plan                       # Plan: 2 to add
./lab.sh tf 01 apply -auto-approve        # (remova -auto-approve para ver o prompt "yes")
./lab.sh tf 01 output                     # config_file = "./output/dev-<nome>.conf"; server_name = "<nome>"
cat terraform/01-local-basics/output/*.conf
./lab.sh tf 01 state list                 # local_file.config, random_pet.server
./lab.sh tf 01 apply -var environment=hml -auto-approve   # muda variável: plano de substituir o arquivo (nome muda)
./lab.sh tf 01 apply -var environment=xyz                 # ERRO esperado: "environment deve ser dev, hml ou prd." (validation)
```
**Simular drift:**
```bash
echo "alterado na mão" >> terraform/01-local-basics/output/*.conf
./lab.sh tf 01 plan                       # o Terraform detecta e propõe recriar o arquivo (volta ao desejado)
./lab.sh tf 01 apply -auto-approve        # corrige o drift
```
**Limpar:** `./lab.sh tf 01 destroy -auto-approve`.

## 4. Exercício 2 — Terraform gerenciando Kubernetes (`terraform/02-kubernetes`)
Namespace `tf-demo`, ConfigMap, Deployment (nginx, 2 réplicas) e Service no cluster Kind. É o mesmo fluxo de um cluster AKS/EKS: muda só o provider/credenciais. Requer `./lab.sh start k8s`.
```bash
./lab.sh tf 02 init
./lab.sh tf 02 plan                                  # Plan: 4 to add
./lab.sh tf 02 apply -auto-approve
kubectl --context kind-lab -n tf-demo get deploy,svc,cm
./lab.sh tf 02 output                                # namespace, service_dns
```
**Drift real (alguém usou kubectl "na mão"):**
```bash
kubectl --context kind-lab -n tf-demo scale deploy/web --replicas=5
./lab.sh tf 02 plan                                  # ~ spec[0].replicas = "5" -> "2"   Plan: 0 to add, 1 to change
./lab.sh tf 02 apply -auto-approve                   # volta para 2
```
**Mudar via código:** `./lab.sh tf 02 apply -var replicas=3 -auto-approve` → `kubectl -n tf-demo get deploy` mostra 3/3.
**Destruir:** `./lab.sh tf 02 destroy -auto-approve` (remove só os 4 recursos do state; o namespace some junto).

## 5. Lendo um plano
```
  # kubernetes_deployment.web will be updated in-place
  ~ resource "kubernetes_deployment" "web" {
      ~ spec { ~ replicas = "5" -> "2" }
Plan: 0 to add, 1 to change, 0 to destroy.
```
`will be updated in-place` = sem downtime; `must be replaced` (`-/+`) = destruir e recriar — **leia com atenção em bancos/discos**. `(known after apply)` = valor só existe após criar.

## 6. Boas práticas
- Versione `.tf` e `.terraform.lock.hcl`; **não** versione `.tfstate` nem `*.tfvars` com segredos (veja `.gitignore`).
- Remote state com lock e criptografia; um state por ambiente/camada; nunca edite o state à mão.
- `terraform plan` em PR (CI) e `apply` só do plano aprovado; revisão obrigatória.
- Fixe versões de providers (`~>`); use módulos para padronizar; `validate` + `fmt` + `tflint`/`checkov`/`trivy config` no CI.
- Nada de segredos em variáveis em texto: use Key Vault/Secrets Manager e `sensitive = true`.
- Tags/labels consistentes; `prevent_destroy` em recursos críticos; mudanças pequenas e frequentes.
- Evite `terraform taint`/`-target` como rotina; é exceção.

## 7. Terraform na nuvem (comparativo, não executado aqui)
| Local (lab) | AWS | Azure |
|---|---|---|
| provider `kubernetes` + Kind | provider `aws` (`aws_eks_cluster`) | provider `azurerm` (`azurerm_kubernetes_cluster`) |
| state local | S3 + DynamoDB lock | Storage Account (Blob) com lease |
| sem credenciais | IAM role/profile | Service Principal / Managed Identity / Workload Identity federation (OIDC) |
Exemplo (AKS, apenas leitura): bloco `resource "azurerm_kubernetes_cluster" "aks" { name=..., default_node_pool { node_count = 2 ... } identity { type = "SystemAssigned" } }`.

## 8. Perguntas de entrevista
1. O que acontece se o state for perdido? (Terraform tenta recriar; usar `import`/backup/versionamento do bucket.)
2. Como evitar dois `apply` simultâneos? (lock do backend.) 3. `plan` mostra recriação inesperada — o que fazer? (`lifecycle`, `ignore_changes`, revisar mudança de atributo imutável.)
4. Diferença entre Terraform e Ansible/CloudFormation/Bicep? 5. Como tratar segredos e state sensível?
