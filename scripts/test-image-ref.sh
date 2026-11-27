#!/usr/bin/env bash
#
# Testa como o chart (e o kustomize) montam a referencia da imagem:
# digest OU tag, nunca "repo:tag@digest", e configuracoes invalidas recusadas.
#
# Uso: bash scripts/test-image-ref.sh   (requer helm; kubectl opcional)
set -u

CHART=charts/wallet
REPO=ghcr.io/eriksonwilliam/go-wallet-pix
DIGEST=sha256:1bbe1dd6ef673bcfd5a305f6c74aed411c6f89cf948762c382d55a861b3d6387
APP_VERSION=$(awk '/^appVersion:/ {gsub(/"/, "", $2); print $2}' "$CHART/Chart.yaml")
failures=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

image_of() {
  helm template wallet "$CHART" "$@" 2>/dev/null | awk '/^ *image: / {gsub(/"/, "", $2); print $2}'
}

expect_image() {
  local name="$1" expected="$2"
  shift 2
  local got
  got=$(image_of "$@")
  if [ "$got" = "$expected" ]; then pass "$name -> $got"; else fail "$name: esperado '$expected', obtido '$got'"; fi
}

expect_rejected() {
  local name="$1"
  shift
  if helm template wallet "$CHART" "$@" >/dev/null 2>&1; then
    fail "$name: deveria ter sido recusado"
  else
    pass "$name (recusado)"
  fi
}

# Valores validos
expect_image "valores padrao usam a tag do appVersion" "$REPO:$APP_VERSION"
expect_image "dev usa a tag do appVersion" "$REPO:$APP_VERSION" -f "$CHART/values-dev.yaml"
expect_image "prod usa exatamente o digest validado" "$REPO@$DIGEST" -f "$CHART/values-prod.yaml"
expect_image "tag explicita sem digest" "$REPO:9.9.9" --set image.tag=9.9.9

# Nunca combinar tag e digest
prod=$(image_of -f "$CHART/values-prod.yaml")
case "$prod" in
  *:*@*) fail "prod combina tag e digest: $prod" ;;
  *) pass "prod nao combina tag e digest" ;;
esac
expect_rejected "prod com tag adicional (schema)" -f "$CHART/values-prod.yaml" --set image.tag=0.2.0
expect_rejected "digest e tag juntos (schema)" --set image.digest="$DIGEST" --set image.tag=0.2.0
if helm template wallet "$CHART" --skip-schema-validation --set image.digest="$DIGEST" --set image.tag=0.2.0 2>&1 \
  | grep -q "mutuamente exclusivos"; then
  pass "digest e tag juntos (template, mesmo sem schema) recusado com mensagem propria"
else
  fail "digest e tag juntos (template, sem schema) deveria falhar com mensagem propria"
fi

# Formatos invalidos
expect_rejected "digest curto" --set image.digest=sha256:abc
expect_rejected "digest sem prefixo" --set image.digest=1bbe1dd6ef673bcfd5a305f6c74aed411c6f89cf948762c382d55a861b3d6387
expect_rejected "digest em maiusculas" --set image.digest=sha256:1BBE1DD6EF673BCFD5A305F6C74AED411C6F89CF948762C382D55A861B3D6387
expect_rejected "tag latest" --set image.tag=latest

# Kustomize (opcional: so roda com kubectl disponivel)
if command -v kubectl >/dev/null 2>&1; then
  for overlay in dev prod; do
    got=$(kubectl kustomize "kustomize/overlays/$overlay" | awk '/^ *image: / {print $2}')
    if [ "$got" = "$REPO@$DIGEST" ]; then pass "kustomize $overlay -> $got"; else fail "kustomize $overlay: obtido '$got'"; fi
  done
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "$failures teste(s) falharam"
  exit 1
fi
echo "todos os testes passaram"
