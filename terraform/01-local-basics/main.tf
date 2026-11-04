# Exercício 1: conceitos de Terraform SEM nenhuma nuvem e SEM cluster.
# Providers "local" e "random" criam arquivos e valores aleatórios na sua máquina.
terraform {
  required_version = ">= 1.5"
  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.5" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

variable "environment" {
  type        = string
  description = "Nome do ambiente (dev, hml, prd)"
  default     = "dev"
  validation {
    condition     = contains(["dev", "hml", "prd"], var.environment)
    error_message = "environment deve ser dev, hml ou prd."
  }
}

variable "replicas" {
  type    = number
  default = 2
}

# resource: algo que o Terraform cria e gerencia
resource "random_pet" "server" {
  length = 2
}

# dependência implícita: usa o resultado de random_pet, então é criado depois dele
resource "local_file" "config" {
  filename = "${path.module}/output/${var.environment}-${random_pet.server.id}.conf"
  content  = <<-EOT
    # gerado pelo Terraform
    environment = ${var.environment}
    replicas    = ${var.replicas}
    server_name = ${random_pet.server.id}
  EOT
}

output "config_file" {
  description = "Arquivo gerado"
  value       = local_file.config.filename
}

output "server_name" {
  value = random_pet.server.id
}
