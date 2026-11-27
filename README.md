# k8s-gitops-platform

Plataforma **Kubernetes / GitOps** que faz o deploy do serviço
[go-wallet-pix](https://github.com/eriksonwilliam/go-wallet-pix), reunindo os
padrões de infraestrutura declarativa mais usados no mercado:

- **Helm** — chart parametrizável do serviço (dev/prod)
- **Kustomize** — mesma app via base + overlays (dev/prod)
- **ArgoCD** — GitOps com o padrão *app-of-apps*
- **Terraform** — bootstrap do cluster: namespaces e ArgoCD
- **Observabilidade** — Prometheus + Grafana (kube-prometheus-stack), gerenciada pelo ArgoCD

Tudo é **validado na CI e localmente** (helm lint, kubeconform, kustomize
build, terraform validate) — não é YAML "de enfeite".

## Estrutura

```
charts/wallet/          # Helm chart do serviço (deployment, service, hpa, ingress,
│                       # servicemonitor, pdb, networkpolicy)
├── values.schema.json  # tipos e restrições dos valores (recusa image.tag=latest)
├── values.yaml         # valores padrão
├── values-dev.yaml     # overlay de desenvolvimento
└── values-prod.yaml    # overlay de produção (HPA, TLS, ServiceMonitor, PDB, NetworkPolicy)

kustomize/              # Alternativa declarativa em Kustomize
├── base/               # deployment + service
└── overlays/           # dev (1 réplica) e prod (3 réplicas)

argocd/                 # GitOps
├── project.yaml        # AppProject `platform` (observabilidade, app-of-apps)
├── project-wallet.yaml # AppProject `wallet`: só o namespace wallet e recursos listados
├── app-of-apps.yaml    # Application raiz que gerencia as demais
└── apps/               # wallet (Helm) + observability (kube-prometheus-stack)

terraform/              # Bootstrap do cluster: namespaces + ArgoCD
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

### 1. Bootstrap com Terraform (instala o ArgoCD)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # ajuste kubeconfig/contexto
terraform init
terraform apply
```

### 2. Ativar o GitOps (app-of-apps)

```bash
kubectl apply -f argocd/project.yaml -f argocd/project-wallet.yaml
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

## Segurança

- **Dois AppProjects.** A wallet roda no projeto `wallet`, que só pode
  escrever no namespace `wallet` e só os tipos de recurso que o chart usa. O
  projeto `platform` precisa de recursos de cluster (CRDs e ClusterRoles do
  kube-prometheus-stack), mas os destinos dele são namespaces explícitos, não `*`.
- **Pod**: não-root (`65532:65532`), `readOnlyRootFilesystem`, sem
  capabilities, `seccomp RuntimeDefault` e sem token de ServiceAccount montado
  (o serviço não fala com a API do Kubernetes).
- **NetworkPolicy** (prod): entrada só do ingress controller e do namespace
  `observability`; saída só para DNS.
- **PodDisruptionBudget** (prod): `minAvailable: 1` durante drains.
- **Imagem por digest**: em produção o chart referencia
  `ghcr.io/eriksonwilliam/go-wallet-pix@sha256:1bbe1dd6…3d6387` (go-wallet-pix
  0.2.0), e o kustomize usa o mesmo digest. Tag no registry pode ser
  sobrescrita; digest não. `image.digest` e `image.tag` são mutuamente
  exclusivos: o `values.schema.json` recusa os dois juntos, um digest fora do
  formato `sha256:<64 hex>` e `image.tag=latest`, e o template falha com
  mensagem própria mesmo sem validação de schema.
  `scripts/test-image-ref.sh` testa esses casos (CI e `make image-ref`).
- **CI**: Trivy nos manifests renderizados e no Terraform, falhando em
  MEDIUM ou acima. As duas exceções aceitas estão justificadas em
  `.trivyignore`.

## Validação em cluster descartável (26/11/2026)

O chart de produção foi instalado num cluster [kind](https://kind.sigs.k8s.io/)
v0.27 (Kubernetes 1.32), com a imagem do go-wallet-pix construída a partir do
PR que adiciona `/metrics` e com o CRD do ServiceMonitor instalado:

| Verificação | Resultado |
| --- | --- |
| `helm install -f values-prod.yaml --wait` | Deployment, Service, HPA, PDB, NetworkPolicy, ServiceMonitor e ServiceAccount criados |
| Réplicas | o Deployment sobe com 1 (sem `replicas` quando há HPA); o HPA impõe `minReplicas` e chega a 3/3 em ~20 s, mesmo sem metrics-server |
| PDB | 2 disrupções permitidas com 3 réplicas |
| `/health`, depósito com `Idempotency-Key`, `/metrics` via port-forward | 200 |
| NetworkPolicy, pod no namespace `default` | **bloqueado** |
| NetworkPolicy, pod no namespace `observability` | alcança `/metrics` |

**Não validado**: sync pelo ArgoCD (o `repoURL` aponta para a `main` e a
imagem ainda não está publicada no GHCR), Ingress com TLS (cert-manager) e
scraping de verdade pelo Prometheus Operator.

## Notas

- A imagem referenciada é `ghcr.io/eriksonwilliam/go-wallet-pix`, versão 0.2.0,
  publicada no GHCR pelo workflow manual do go-wallet-pix (pacote público, sem
  `imagePullSecret`). Este repositório ainda não foi aplicado em nenhum cluster
  real; a única execução foi a validação em kind descrita acima.
- O `ServiceMonitor` fica desligado por padrão e ligado em prod. A imagem
  usada precisa conter o endpoint `/metrics` (go-wallet-pix depois do PR que o
  adicionou); com uma imagem anterior o alvo fica permanentemente `down`.
- O Terraform usa state local: é bootstrap de laboratório. Num ambiente real,
  backend remoto com lock (S3 + DynamoDB, por exemplo) e um state por ambiente.
- O ArgoCD sobe com `server.insecure=true` (TLS terminado fora dele), o que é
  adequado só para laboratório local.

## Licença

MIT.
