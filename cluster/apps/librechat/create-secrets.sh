#!/usr/bin/env bash
# Create the librechat namespace and the `librechat-secrets` Secret (LibreChat's
# credential/JWT keys + the dummy Anthropic key) from the encrypted env. Idempotent.
# Argo does NOT manage secrets; run this once (and after rotating the keys):
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   export KUBECONFIG=/root/.kube/config
#   cluster/apps/librechat/create-secrets.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
: "${SOPS_AGE_KEY_FILE:?}"

kubectl create namespace librechat --dry-run=client -o yaml | kubectl apply -f -

# LibreChat's keys. --from-env-file takes values literally; the values we generate
# are bare hex/tokens with no quotes, so no dotenv-quote stripping is needed here.
env_plain="$(mktemp)"; trap 'rm -f "$env_plain"' EXIT
sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/librechat.env.enc" > "$env_plain"
kubectl -n librechat create secret generic librechat-secrets --from-env-file="$env_plain" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "librechat: namespace + librechat-secrets created."
