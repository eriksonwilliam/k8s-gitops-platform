variable "kubeconfig_path" {
  description = "Caminho para o kubeconfig do cluster alvo."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexto do kubeconfig a usar (vazio = contexto atual)."
  type        = string
  default     = ""
}

variable "wallet_namespace" {
  description = "Namespace da aplicacao wallet."
  type        = string
  default     = "wallet"
}

variable "argocd_chart_version" {
  description = "Versao do chart argo-cd (argo-helm)."
  type        = string
  default     = "7.7.5"
}
