# k8s-gitops-platform

Plataforma **Kubernetes / GitOps** que faz o deploy do serviço
[go-wallet-pix](https://github.com/eriksonwilliam/go-wallet-pix), reunindo os
padrões de infraestrutura declarativa mais usados no mercado:

- **Helm** — chart parametrizável do serviço (dev/prod)
- **Kustomize** — mesma app via base + overlays (dev/prod)
- **ArgoCD** — GitOps com o padrão *app-of-apps*
- **Terraform** — provisiona ArgoCD e a stack de observabilidade no cluster
- **Observabilidade** — Prometheus + Grafana (kube-prometheus-stack)

Tudo é **validado na CI e localmente** (helm lint, kubeconform, kustomize
build, terraform validate) — não é YAML "de enfeite".

## Estrutura

```
charts/wallet/          # Helm chart do serviço (deployment, service, hpa, ingress, servicemonitor)
├── values.yaml         # valores padrão
├── values-dev.yaml     # overlay de desenvolvimento
└── values-prod.yaml    # overlay de produção (HPA, TLS, ServiceMonitor)

kustomize/              # Alternativa declarativa em Kustomize
├── base/               # deployment + service
└── overlays/           # dev (1 réplica) e prod (3 réplicas)

argocd/                 # GitOps
├── project.yaml        # AppProject
├── app-of-apps.yaml    # Application raiz que gerencia as demais
└── apps/               # wallet (Helm) + observability (kube-prometheus-stack)

terraform/              # Bootstrap do cluster: ArgoCD + observabilidade
```

## Como validar (local)

Requer `helm`, `kubectl`, `kubeconform` e `terraform` no PATH.

```bash
make validate
```

Isso roda, em sequência:

- `helm lint` do chart nos três conjuntos de valores
- `helm template ... | kubeconform` (schemas do Kubernetes)
- `kubectl kustomize` dos overlays dev/prod + kubeconform
- `kubeconform` nos manifests do ArgoCD
- `terraform fmt -check`, `init -backend=false` e `validate`

## Como aplicar (em um cluster)

### 1. Bootstrap com Terraform (instala ArgoCD + observabilidade)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste kubeconfig/contexto
terraform init
terraform apply
```

### 2. Ativar o GitOps (app-of-apps)

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-of-apps.yaml
```

A partir daí o ArgoCD sincroniza sozinho a `wallet` (via Helm) e a stack de
observabilidade, seguindo o que está versionado neste repositório.

### Alternativa sem Helm/ArgoCD (Kustomize puro)

```bash
kubectl apply -k kustomize/overlays/dev
```

## Deploy manual do chart (sem ArgoCD)

```bash
helm upgrade --install wallet charts/wallet \
  -n wallet --create-namespace \
  -f charts/wallet/values-prod.yaml
```

## Notas

- A imagem referenciada é `ghcr.io/eriksonwilliam/go-wallet-pix`. Publique-a
  (ex.: via GitHub Actions no repositório do serviço) antes de aplicar em um
  cluster real.
- O `ServiceMonitor` do chart fica **desabilitado por padrão**: ele pressupõe
  que a aplicação exponha `/metrics`. Habilite-o (`serviceMonitor.enabled=true`)
  quando o serviço publicar o endpoint de métricas.

## Licença

MIT.
