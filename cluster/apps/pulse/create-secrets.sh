#!/usr/bin/env bash
# Create the pulse namespace, the GHCR pull secret, pulse-secrets (the whole app
# env), and pulse-jwt (the RS256 signing key mounted as a file). Idempotent.
# Run with KUBECONFIG set and the sops env available:
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   set -a; eval "$(sops -d secrets/homelab.enc.env)"; set +a   # for GIT_HTTP_TOKEN
#   cluster/apps/pulse/create-secrets.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=/dev/null
[ -n "${GIT_HTTP_TOKEN:-}" ] || . "$REPO_ROOT/scripts/load-env.sh"
: "${GIT_HTTP_TOKEN:?}" "${SOPS_AGE_KEY_FILE:?}"

kubectl create namespace pulse --dry-run=client -o yaml | kubectl apply -f -

# pull images from GHCR
kubectl -n pulse create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username="${GIT_HTTP_USERNAME:-x-access-token}" \
  --docker-password="${GIT_HTTP_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# the whole Pulse env (its DSN already points at our postgres LXC + redis service)
env_plain="$(mktemp)"; trap 'rm -f "$env_plain"' EXIT
sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/pulse.env.enc" > "$env_plain"
kubectl -n pulse create secret generic pulse-secrets --from-env-file="$env_plain" \
  --dry-run=client -o yaml | kubectl apply -f -

# JWT signing key, mounted as a file at PULSE_JWT_PRIVATE_KEY_PATH (see api.yaml)
jwt_plain="$(mktemp)"
sops -d --input-type binary --output-type binary "$REPO_ROOT/secrets/pulse-jwt.key.enc" > "$jwt_plain"
kubectl -n pulse create secret generic pulse-jwt --from-file=jwt-private.pem="$jwt_plain" \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f "$jwt_plain"

echo "pulse: namespace + ghcr pull secret + pulse-secrets + pulse-jwt created."
