#!/usr/bin/env bash
#
# Confere o ruleset da main (.github/rulesets/main.json) contra a CI: cada
# check obrigatorio precisa ser o nome de um job do workflow. Um nome que nao
# existe deixaria todo PR esperando um check que nunca roda.
#
# Uso: bash scripts/test-ruleset.sh
set -u

RULESET=.github/rulesets/main.json
WORKFLOW=.github/workflows/ci.yml
failures=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failures=$((failures + 1)); }

jobs=$(awk '/^jobs:/ { inside = 1; next } inside && /^    name:/ { sub(/^    name: */, ""); print }' "$WORKFLOW")
checks=$(grep -o '"context": *"[^"]*"' "$RULESET" | sed 's/.*"context": *"//; s/"$//')

if [ -z "$checks" ]; then
  fail "ruleset com checks obrigatorios"
fi
while IFS= read -r check; do
  [ -z "$check" ] && continue
  if echo "$jobs" | grep -qxF "$check"; then
    pass "check obrigatorio \"$check\" existe na CI"
  else
    fail "check obrigatorio \"$check\" existe na CI"
  fi
done <<<"$checks"

for rule in deletion non_fast_forward pull_request required_status_checks; do
  if grep -q "\"type\": \"$rule\"" "$RULESET"; then pass "regra $rule"; else fail "regra $rule"; fi
done

if grep -q '"bypass_actors": \[\]' "$RULESET"; then
  pass "sem bypass (vale tambem para administradores)"
else
  fail "sem bypass (vale tambem para administradores)"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures falha(s)"
  exit 1
fi
echo "todas as regras passaram"
