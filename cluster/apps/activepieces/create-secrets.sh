#!/usr/bin/env bash
# Create the activepieces namespace and activepieces-secrets (the whole app
# env). Idempotent. Run with KUBECONFIG set and the sops env available:
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   cluster/apps/activepieces/create-secrets.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
: "${SOPS_AGE_KEY_FILE:?}"

kubectl create namespace activepieces --dry-run=client -o yaml | kubectl apply -f -

# the whole Activepieces env (its DSN already points at postgres.internal + the
# in-cluster redis service). kubectl --from-env-file takes each value literally
# and does NOT strip dotenv quotes, so strip one layer of surrounding matched
# quotes before handing it to kubectl (same as pulse's create-secrets.sh).
env_plain="$(mktemp)"; trap 'rm -f "$env_plain"' EXIT
sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/activepieces.env.enc" \
  | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)="(.*)"$/\1=\2/; s/^([A-Za-z_][A-Za-z0-9_]*)='"'"'(.*)'"'"'$/\1=\2/' \
  > "$env_plain"
kubectl -n activepieces create secret generic activepieces-secrets --from-env-file="$env_plain" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "activepieces: namespace + activepieces-secrets created."
