#!/usr/bin/env bash
#
# Testa as regras de menor privilegio e de ordem de sync do ArgoCD:
# nenhum "*" nas whitelists, so o projeto bootstrap escreve no namespace
# argocd, raiz sem prune, ondas na ordem certa, retry, ServiceMonitor sem
# dry-run quando o CRD falta, health de Application no ArgoCD e a whitelist
# do projeto platform cobrindo tudo o que o kube-prometheus-stack renderiza.
#
# Uso: bash scripts/test-argocd-policy.sh   (requer helm e acesso ao repo do chart)
set -u

failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

# Valor de uma anotacao ou campo simples ("chave: valor") num arquivo.
field() { awk -v key="$2" '$1 == key":" { v = $2; gsub(/"/, "", v); print v; exit }' "$1"; }

# Namespaces listados em spec.destinations de um AppProject.
destinations() {
  awk '/^  destinations:/ { inside = 1; next } inside && /^  [a-zA-Z]/ { inside = 0 } inside && /namespace:/ { print $2 }' "$1"
}

# "grupo/Kind" de uma whitelist (clusterResourceWhitelist ou namespaceResourceWhitelist).
whitelist() {
  awk -v list="$2" '
    $0 ~ "^  " list ":" { inside = 1; next }
    inside && /^  [a-zA-Z]/ { inside = 0 }
    inside && /group:/ { g = $3; gsub(/"/, "", g) }
    inside && /kind:/ { print g "/" $2 }
  ' "$1"
}

if grep -rnE '(group|kind): "\*"' argocd/ >/dev/null; then
  fail 'nenhuma whitelist com "*"'
else
  pass 'nenhuma whitelist com "*"'
fi

for project in argocd/apps/projects/*.yaml; do
  if destinations "$project" | grep -qx argocd; then
    fail "$project nao tem o namespace argocd como destino"
  else
    pass "$project nao tem o namespace argocd como destino"
  fi
done

if [ "$(destinations argocd/project-bootstrap.yaml)" = "argocd" ] &&
  [ "$(whitelist argocd/project-bootstrap.yaml namespaceResourceWhitelist | sort | tr '\n' ' ')" = "argoproj.io/AppProject argoproj.io/Application " ]; then
  pass "bootstrap so cria Application e AppProject no namespace argocd"
else
  fail "bootstrap so cria Application e AppProject no namespace argocd"
fi

if [ "$(field argocd/app-of-apps.yaml project)" = "bootstrap" ] && [ "$(field argocd/app-of-apps.yaml prune)" = "false" ]; then
  pass "app-of-apps no projeto bootstrap e sem prune"
else
  fail "app-of-apps no projeto bootstrap e sem prune"
fi

wave() { field "$1" argocd.argoproj.io/sync-wave; }
if [ "$(wave argocd/apps/projects/platform.yaml)" = "-1" ] && [ "$(wave argocd/apps/projects/wallet.yaml)" = "-1" ] &&
  [ "$(wave argocd/apps/observability.yaml)" = "0" ] && [ "$(wave argocd/apps/wallet.yaml)" = "1" ]; then
  pass "ondas: projetos (-1), observabilidade (0), wallet (1)"
else
  fail "ondas: projetos (-1), observabilidade (0), wallet (1)"
fi

for app in argocd/apps/observability.yaml argocd/apps/wallet.yaml; do
  if grep -q '^    retry:' "$app" && [ -n "$(field "$app" limit)" ]; then
    pass "$app com retry"
  else
    fail "$app com retry"
  fi
done

if helm template wallet charts/wallet -f charts/wallet/values-prod.yaml 2>/dev/null |
  awk '/^kind: ServiceMonitor/ { sm = 1 } sm && /SkipDryRunOnMissingResource=true/ { found = 1 } END { exit !found }'; then
  pass "ServiceMonitor com SkipDryRunOnMissingResource"
else
  fail "ServiceMonitor com SkipDryRunOnMissingResource"
fi

if grep -q 'resource.customizations.health.argoproj.io_Application' terraform/main.tf; then
  pass "health de Application configurado no ArgoCD"
else
  fail "health de Application configurado no ArgoCD"
fi

# Todo tipo que o chart renderiza precisa estar na whitelist do platform,
# senao o sync falha. O Pod de teste do Helm (hook) e ignorado pelo ArgoCD.
chart=$(field argocd/apps/observability.yaml chart)
version=$(field argocd/apps/observability.yaml targetRevision)
repo=$(field argocd/apps/observability.yaml repoURL)
rendered=$(helm template obs "$chart" --repo "$repo" --version "$version" --namespace observability --include-crds 2>/dev/null |
  awk '
    function flush() { if (k != "") print g "/" k; g = ""; k = "" }
    /^---/ { flush(); next }
    /^apiVersion:/ { g = $2; sub(/\/?v[0-9a-z]+$/, "", g) }
    /^kind:/ { k = $2 }
    END { flush() }
  ' | sort -u)
if [ -z "$rendered" ]; then
  fail "render do $chart $version (sem acesso ao repositorio do chart?)"
else
  allowed=$( (whitelist argocd/apps/projects/platform.yaml clusterResourceWhitelist; whitelist argocd/apps/projects/platform.yaml namespaceResourceWhitelist) | sort -u)
  missing=$(comm -23 <(echo "$rendered" | grep -v '^/Pod$') <(echo "$allowed"))
  if [ -z "$missing" ]; then
    pass "whitelist do platform cobre o $chart $version"
  else
    fail "whitelist do platform cobre o $chart $version; faltam: $(echo "$missing" | tr '\n' ' ')"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures falha(s)"
  exit 1
fi
echo "todas as regras passaram"
