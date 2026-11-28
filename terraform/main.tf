provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context != "" ? var.kube_context : null
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context != "" ? var.kube_context : null
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace" "wallet" {
  metadata {
    name = var.wallet_namespace
  }
}

resource "kubernetes_namespace" "observability" {
  metadata {
    name = "observability"
  }
}

# ArgoCD: a partir daqui o GitOps assume (app-of-apps aponta para este repo).
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # Health de Application: sem isto o ArgoCD (1.8+) nao avalia a saude das
  # Applications filhas, e as sync-waves do app-of-apps nao esperam a
  # observabilidade (CRDs) ficar pronta antes da wallet.
  values = [yamlencode({
    configs = {
      cm = {
        "resource.customizations.health.argoproj.io_Application" = <<-EOT
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil and obj.status.health ~= nil then
            hs.status = obj.status.health.status
            if obj.status.health.message ~= nil then
              hs.message = obj.status.health.message
            end
          end
          return hs
        EOT
      }
    }
  })]
}

# Observabilidade (kube-prometheus-stack) NAO e instalada aqui: quem a
# gerencia e a Application `observability` do ArgoCD. Instalar pelos dois
# lados criava duas releases do mesmo chart no mesmo namespace, com dois
# operators disputando CRDs e webhooks. O Terraform so cria o que precisa
# existir antes do GitOps: namespaces e o proprio ArgoCD.
