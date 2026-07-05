output "argocd_namespace" {
  description = "Namespace onde o ArgoCD foi instalado."
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "wallet_namespace" {
  description = "Namespace da aplicacao wallet."
  value       = kubernetes_namespace.wallet.metadata[0].name
}

output "observability_namespace" {
  description = "Namespace da stack de observabilidade."
  value       = kubernetes_namespace.observability.metadata[0].name
}
