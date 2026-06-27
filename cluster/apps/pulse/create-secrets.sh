#!/usr/bin/env bash
# Create the pulse namespace, GHCR pull secret, and pulse-secrets from the
# decrypted env. Run once (and after rotation) with KUBECONFIG set and the env
# sourced. Nothing secret is committed; this reuses the age-decrypted env.
set -euo pipefail
: "${PULSE_DB_PASSWORD:?}" "${PULSE_SECRET_KEY:?}" "${GIT_HTTP_TOKEN:?}"

kubectl create namespace pulse --dry-run=client -o yaml | kubectl apply -f -

# pull images from your GHCR
kubectl -n pulse create secret docker-registry ghcr \
  --docker-server=ghcr.io \
  --docker-username="${GIT_HTTP_USERNAME:-x-access-token}" \
  --docker-password="${GIT_HTTP_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

# postgres LXC over the LAN
dsn="postgres://pulse:${PULSE_DB_PASSWORD}@192.168.178.102:5432/pulse?sslmode=disable"

kubectl -n pulse create secret generic pulse-secrets \
  --from-literal=PULSE_POSTGRES_DSN="$dsn" \
  --from-literal=PULSE_SECRET_KEY="$PULSE_SECRET_KEY" \
  --from-literal=PULSE_JWT_PRIVATE_KEY_PEM="${PULSE_JWT_PRIVATE_KEY_PEM:-}" \
  --from-literal=PULSE_GOOGLE_CLIENT_ID="${PULSE_GOOGLE_CLIENT_ID:-}" \
  --from-literal=PULSE_GOOGLE_CLIENT_SECRET="${PULSE_GOOGLE_CLIENT_SECRET:-}" \
  --from-literal=PULSE_GITHUB_CLIENT_ID="${PULSE_GITHUB_CLIENT_ID:-}" \
  --from-literal=PULSE_GITHUB_CLIENT_SECRET="${PULSE_GITHUB_CLIENT_SECRET:-}" \
  --from-literal=PULSE_SMTP_PASSWORD="${PULSE_SMTP_PASSWORD:-}" \
  --from-literal=PULSE_BILLING_WEBHOOK_SECRET="${PULSE_BILLING_WEBHOOK_SECRET:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "pulse namespace, ghcr pull secret, and pulse-secrets created."
