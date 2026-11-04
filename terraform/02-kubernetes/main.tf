# Exercício 2: Terraform gerenciando recursos Kubernetes no cluster Kind (contexto kind-lab).
# É o mesmo fluxo que você usaria para AKS/EKS, trocando apenas o provider/credenciais.
terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-lab"
}

variable "namespace" {
  type    = string
  default = "tf-demo"
}

variable "replicas" {
  type    = number
  default = 2
}

variable "image" {
  type    = string
  default = "nginx:1.27-alpine"
}

resource "kubernetes_namespace" "this" {
  metadata { name = var.namespace }
}

resource "kubernetes_config_map" "page" {
  metadata {
    name      = "page"
    namespace = kubernetes_namespace.this.metadata[0].name # dependência implícita
  }
  data = { "index.html" = "<h1>Criado pelo Terraform</h1>" }
}

resource "kubernetes_deployment" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace.this.metadata[0].name
    labels    = { app = "web" }
  }
  spec {
    replicas = var.replicas
    selector { match_labels = { app = "web" } }
    template {
      metadata { labels = { app = "web" } }
      spec {
        container {
          name  = "nginx"
          image = var.image
          port { container_port = 80 }
          resources {
            requests = { cpu = "10m", memory = "16Mi" }
            limits   = { memory = "64Mi" }
          }
          volume_mount {
            name       = "page"
            mount_path = "/usr/share/nginx/html"
          }
        }
        volume {
          name = "page"
          config_map { name = kubernetes_config_map.page.metadata[0].name }
        }
      }
    }
  }
}

resource "kubernetes_service" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace.this.metadata[0].name
  }
  spec {
    selector = { app = "web" }
    port {
      port        = 80
      target_port = 80
    }
  }
}

output "namespace" { value = kubernetes_namespace.this.metadata[0].name }
output "service_dns" { value = "${kubernetes_service.web.metadata[0].name}.${var.namespace}.svc.cluster.local" }
