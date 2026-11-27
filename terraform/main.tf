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
}

# Observabilidade (kube-prometheus-stack) NAO e instalada aqui: quem a
# gerencia e a Application `observability` do ArgoCD. Instalar pelos dois
# lados criava duas releases do mesmo chart no mesmo namespace, com dois
# operators disputando CRDs e webhooks. O Terraform so cria o que precisa
# existir antes do GitOps: namespaces e o proprio ArgoCD.
