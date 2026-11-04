# 09 — Conceitos de Cloud: AWS e Azure

Nada aqui é provisionado: é o mapa entre o que você praticou localmente e os serviços equivalentes. Comandos `aws`/`az` são para **conhecer** (exigem conta; não são executados no lab).

## 1. Mapa geral: local → nuvem
| No lab | AWS | Azure |
|---|---|---|
| Sua máquina / container Docker | EC2 | Virtual Machines |
| Kind | EKS | AKS |
| Imagens locais (`kind load`) | ECR | ACR |
| Docker Compose/containers simples | ECS / Fargate | Container Apps / ACI |
| Service LoadBalancer / Ingress | ELB (ALB/NLB) | Load Balancer / Application Gateway |
| `/etc/resolv.conf`, CoreDNS | Route 53 (+ Private Zones) | Azure DNS / Private DNS |
| Firewall do host | Security Group / NACL | NSG / Azure Firewall |
| Terraform local state | S3 + DynamoDB | Storage Account (Blob) |
| Prometheus+Grafana+Loki | CloudWatch (+ Managed Prometheus/Grafana) | Azure Monitor / Log Analytics / Application Insights |
| Secret do K8s | Secrets Manager / SSM Parameter Store | Key Vault |
| Jenkins | CodePipeline/CodeBuild (ou Jenkins em EC2/EKS) | Azure DevOps Pipelines / GitHub Actions |
| Trivy/Sonar | Inspector, ECR scanning | Defender for Cloud / Defender for Containers |

## 2. EC2 × Azure Virtual Machines
| Aspecto | EC2 | Azure VM |
|---|---|---|
| Tipo/tamanho | instance type (`t3.medium`) | VM size (`Standard_D2s_v5`) |
| Imagem | AMI | Image (Marketplace / Compute Gallery) |
| Disco | EBS (gp3, io2), instance store | Managed Disks (Premium SSD, Standard) |
| Rede | VPC, subnet, Security Group, ENI | VNet, subnet, NSG, NIC |
| Acesso | Key Pair SSH, SSM Session Manager | SSH key, Azure Bastion, Run Command |
| Escala | Auto Scaling Group | VM Scale Sets (VMSS) |
| Identidade da VM | Instance Profile (IAM Role) | Managed Identity |
| Bootstrap | User Data / cloud-init | Custom Script Extension / cloud-init |
| Alta disponibilidade | múltiplas AZs | Availability Zones / Availability Sets |
| Cobrança | on-demand, Reserved, Savings Plans, Spot | pay-as-you-go, Reservations, Savings Plan, Spot |
Troubleshooting idêntico ao do [02](02-LINUX-AND-NETWORKING.md): `ss`, `df`, `journalctl`… A diferença é *chegar* na máquina (SSM/Bastion) e a rede em volta (SG/NSG, rotas, DNS da VPC/VNet).
```bash
aws ec2 describe-instances --query 'Reservations[].Instances[].[InstanceId,State.Name]'      # conhecer
az vm list -o table
```

## 3. EKS × AKS
| Aspecto | EKS | AKS |
|---|---|---|
| Control plane | gerenciado (cobrado por hora) | gerenciado (Free tier sem custo; Standard com SLA) |
| Nodes | Managed Node Groups / Karpenter / Fargate | Node Pools (VMSS) / Virtual Nodes |
| Rede de pods | Amazon VPC CNI (IP da VPC por pod) | Azure CNI / CNI Overlay / kubenet |
| Entrada | AWS Load Balancer Controller (ALB/NLB) | App Gateway Ingress / App Routing / ingress-nginx |
| Registry | ECR | ACR (`--attach-acr`) |
| Identidade de usuário | IAM → `aws-auth`/Access Entries | Microsoft Entra ID + Azure RBAC for K8s |
| Identidade de pod | IRSA / EKS Pod Identity | Workload Identity (Entra) / Managed Identity |
| Autoscaling | Cluster Autoscaler / Karpenter, HPA | Cluster Autoscaler, HPA, KEDA add-on |
| Upgrade | `eksctl`/console por versão | `az aks upgrade`, auto-upgrade channels |
| Observabilidade | CloudWatch Container Insights | Container Insights (Azure Monitor) |
| Storage | EBS CSI, EFS CSI | Azure Disk/Files CSI |
```bash
aws eks update-kubeconfig --name meu-cluster --region us-east-1     # gera kubeconfig (conhecer)
az aks get-credentials -g rg -n meu-aks
kubectl get nodes       # a partir daqui os comandos são os mesmos do doc 03
```
**Pergunta:** “o que é gerenciado e o que é meu?” → control plane (etcd, API server, scheduler) é do provedor; **seus** são nodes (patch/upgrade/tamanho), rede, RBAC, manifests, add-ons, segurança de workloads.

## 4. IAM × Microsoft Entra ID / RBAC
| Conceito | AWS IAM | Azure |
|---|---|---|
| Diretório de identidades | usuários/roles por conta (IAM Identity Center para SSO) | **Microsoft Entra ID** (antigo Azure AD) por tenant |
| Autorização | **Policies** JSON (Allow/Deny, `Action`, `Resource`, `Condition`) anexadas a user/group/role | **Azure RBAC**: *role definition* + *assignment* (principal + role + **scope**: Management Group → Subscription → Resource Group → Resource) |
| Identidade de workload | IAM Role (Instance Profile, IRSA) | Managed Identity (system/user-assigned), Service Principal |
| Acesso temporário | STS `AssumeRole` | tokens Entra (OAuth2), PIM (just-in-time) |
| Multi-conta/assinatura | AWS Organizations + SCP | Management Groups + Azure Policy |
| Auditoria | CloudTrail | Activity Log / Entra sign-in logs |
Princípios (valem para ambos): **mínimo privilégio**, sem chaves de longa duração (prefira roles/managed identity), MFA, separação por ambientes, revisão periódica. No Kubernetes há uma 3ª camada: **RBAC do K8s** (`Role`/`ClusterRole`/`RoleBinding`) — pratique: `kubectl auth can-i list pods -n demo --as=system:serviceaccount:demo:default`.

## 5. CloudWatch × Azure Monitor
| Necessidade | AWS | Azure | Local (lab) |
|---|---|---|---|
| Métricas | CloudWatch Metrics | Azure Monitor Metrics | Prometheus |
| Logs | CloudWatch Logs (Logs Insights) | Log Analytics (consultas **KQL**) | Loki (LogQL) |
| Alertas | CloudWatch Alarms (+SNS) | Alert rules + Action Groups | regras Prometheus |
| Traces/APM | X-Ray / CloudWatch Application Signals | Application Insights | Tempo/OTel |
| Dashboards | CloudWatch Dashboards | Workbooks / Dashboards (Managed Grafana) | Grafana |
| K8s | Container Insights | Container Insights / Managed Prometheus | cAdvisor + Prometheus |
| Auditoria | CloudTrail | Activity Log | — |
Exemplo de consulta equivalente (erros por minuto): LogQL `sum(count_over_time({namespace="demo",level="ERROR"}[1m]))` · KQL `ContainerLog | where LogEntry has "ERROR" | summarize count() by bin(TimeGenerated,1m)` · Logs Insights `filter @message like /ERROR/ | stats count() by bin(1m)`.

## 6. AWS CLI × Azure CLI
| Tarefa | AWS CLI | Azure CLI |
|---|---|---|
| Autenticar | `aws configure` / `aws sso login` | `az login` |
| Quem sou eu | `aws sts get-caller-identity` | `az account show` |
| Escopo | `--profile`, `--region` | `az account set --subscription`, `-g <resource-group>` |
| Listar VMs | `aws ec2 describe-instances` | `az vm list -o table` |
| Cluster K8s | `aws eks update-kubeconfig` | `az aks get-credentials` |
| Logs | `aws logs tail /grupo --follow` | `az monitor log-analytics query` |
| Saída | `--output json|table|text`, `--query` (JMESPath) | `-o json|table|tsv`, `--query` (JMESPath) |
| Ajuda | `aws ec2 help` | `az vm --help` |
Ambos usam JMESPath no `--query`. Dica: sempre confira conta/assinatura ativa **antes** de comandos destrutivos.

## 7. Snapshots e backup
| Necessidade | AWS | Azure |
|---|---|---|
| Disco de VM | **EBS Snapshot** (incremental, no S3 gerenciado), AMI a partir de snapshot | **Managed Disk Snapshot** / Azure Backup (Recovery Services vault) |
| Backup centralizado/políticas | **AWS Backup** | **Azure Backup** / Backup vault |
| Banco gerenciado | RDS automated backups + snapshots, PITR | Azure SQL/PostgreSQL backups automáticos, PITR |
| Objetos | S3 versioning, replicação | Blob versioning, soft delete |
| Kubernetes | Velero (+EBS snapshots), backup de PV | Velero / AKS Backup; PV snapshots via CSI |
| Recuperação entre regiões | cópia de snapshot / replicação | GRS / cópia de snapshot / Site Recovery |
Conceitos: **RPO** (quanto de dado posso perder) e **RTO** (quanto tempo posso ficar fora); snapshot ≠ backup se estiver na mesma conta/região sem cópia; **teste a restauração**. No lab: `./lab.sh stop` preserva volumes; `docker volume ls` mostra os dados (equivalente local de “discos”).

## 8. Deploy e rollback em cloud
| Prática | Local (lab) | Cloud |
|---|---|---|
| Rolling update | `kubectl rollout` | idem em EKS/AKS; ECS rolling; App Service slots |
| Rollback | `kubectl rollout undo` (exercício `rollback`) | idem; **Blue/Green**: ALB trocar target group / Azure traffic manager, App Service **deployment slots swap**; **CodeDeploy** (AWS) com rollback automático por alarme |
| Canary | (não coberto) | ALB weighted target groups, Argo Rollouts/Flagger, Azure Front Door ponderado |
| Pipeline | Jenkins | CodePipeline / Azure DevOps / GitHub Actions |
| Infra | Terraform | Terraform + CloudFormation (AWS) / Bicep-ARM (Azure) |
| Artefato imutável | tag `jenkins-N` | tag imutável no ECR/ACR (ou digest) |
| Segredos | Secret | Secrets Manager / Key Vault |
| Rollback de dados | — | não reverte automaticamente: migrations compatíveis, snapshot antes de mudanças |
Regra de ouro: **rollback = redeploy da versão anterior conhecida-boa**, rápido, com health checks e métricas (Golden Signals) para decidir. Feature flags reduzem a necessidade.

## 9. Perguntas de revisão (AWS/Azure)
1. Região × Availability Zone? (AZ = datacenter(s) isolados dentro da região; espalhe réplicas em ≥2 AZs.) 2. Security Group (stateful, só allow) × NACL (stateless, allow/deny)? NSG é stateful.
3. Como um pod acessa o S3/Key Vault sem chave? (IRSA / Workload Identity.) 4. Como reduzir custo em EKS/AKS? (right-sizing, autoscaler, Spot, desligar ambientes.)
5. Como o tráfego chega a um pod no AKS? (Internet → LB/App Gateway → Ingress → Service → Pod.) 6. Modelo de responsabilidade compartilhada?
