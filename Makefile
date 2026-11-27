HELM ?= helm
KUBECTL ?= kubectl
TERRAFORM ?= terraform
KUBECONFORM ?= kubeconform
KC_FLAGS ?= -strict -ignore-missing-schemas -summary

.PHONY: all validate lint image-ref template kustomize argocd tf-validate

all: validate

validate: lint image-ref template kustomize argocd tf-validate

lint:
	$(HELM) lint charts/wallet
	$(HELM) lint charts/wallet -f charts/wallet/values-dev.yaml
	$(HELM) lint charts/wallet -f charts/wallet/values-prod.yaml

image-ref:
	bash scripts/test-image-ref.sh

template:
	$(HELM) template wallet charts/wallet -f charts/wallet/values-prod.yaml | $(KUBECONFORM) $(KC_FLAGS)

kustomize:
	$(KUBECTL) kustomize kustomize/overlays/dev | $(KUBECONFORM) $(KC_FLAGS)
	$(KUBECTL) kustomize kustomize/overlays/prod | $(KUBECONFORM) $(KC_FLAGS)

argocd:
	$(KUBECONFORM) $(KC_FLAGS) argocd/

tf-validate:
	cd terraform && $(TERRAFORM) fmt -check && $(TERRAFORM) init -backend=false && $(TERRAFORM) validate
