#!/usr/bin/env bash
# Seed (or reset) the single LibreChat login and mirror it to Vaultwarden.
#
# Registration is closed (ALLOW_REGISTRATION=false in config.yaml), so the only
# way in is a user that already exists in Mongo -- and nothing else in the deploy
# creates one. `create-secrets.sh` only builds the JWT/CREDS Secret; Argo manages
# manifests, not DB rows. So a fresh cluster (or a rebuilt, empty Mongo PVC) has
# zero users and every login returns "Email does not exist" until this runs.
#
# Run it AFTER the librechat pod is Running -- it execs the app's own user CLI
# against the live DB. Idempotent: creates the user if absent, otherwise resets
# its password. Either way it generates a fresh password and upserts it into the
# Vaultwarden "homelab" folder, so there is exactly one browsable source of the
# current credential (sops holds the keys; the login password lives in Vaultwarden
# by design, same as other generated app passwords).
#
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   export KUBECONFIG=/root/.kube/config
#   cluster/apps/librechat/seed-user.sh            # email from the sops secret
#   cluster/apps/librechat/seed-user.sh other@x.io # or override the email
set -euo pipefail
: "${SOPS_AGE_KEY_FILE:?}" "${KUBECONFIG:?}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"

# LIBRECHAT_ADMIN_EMAIL lives in the librechat sops secret so the identity is
# declarative; NAME/USERNAME are cosmetic and rarely change.
env_plain="$(sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/librechat.env.enc")"
get() { printf '%s\n' "$env_plain" | grep -m1 "^$1=" | sed -E 's/^[A-Za-z_]+="?(.*[^"])"?$/\1/'; }
EMAIL="${1:-$(get LIBRECHAT_ADMIN_EMAIL)}"
: "${EMAIL:?set LIBRECHAT_ADMIN_EMAIL in secrets/librechat.env.enc or pass the email as an argument}"
NAME="${LIBRECHAT_ADMIN_NAME:-Mert Yildiz}"
USERNAME="${LIBRECHAT_ADMIN_USERNAME:-mert}"

pod="$(kubectl get pods -n librechat -l app=librechat \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[ -n "$pod" ] || { echo "seed-user: no Running librechat pod (deploy the app first)" >&2; exit 1; }

# Freshly generated each run; only ever leaves this script via the app CLI (to
# hash into Mongo) and the Vaultwarden upsert below. Not printed.
PW="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-22)"

if kubectl exec -n librechat "$pod" -- sh -c 'cd /app && npm run list-users 2>/dev/null' \
    | grep -qiF "Email: $EMAIL"; then
  # reset-password.js is prompt-driven: email, new password, confirm.
  printf '%s\n%s\n%s\n' "$EMAIL" "$PW" "$PW" \
    | kubectl exec -i -n librechat "$pod" -- sh -c 'cd /app && node config/reset-password.js' >/dev/null
  echo "librechat: reset password for existing user $EMAIL"
else
  # shellcheck disable=SC2016  # $E/$N/$U/$P expand in the container's sh (via env), not here
  kubectl exec -n librechat "$pod" -- env E="$EMAIL" N="$NAME" U="$USERNAME" P="$PW" \
    sh -c 'cd /app && npm run create-user -- "$E" "$N" "$U" "$P" --email-verified=true' >/dev/null
  echo "librechat: created user $EMAIL"
fi

"$REPO_ROOT/scripts/vaultwarden-upsert.sh" "LibreChat" "$EMAIL" "$PW" \
  "https://ai.mert574.dev" "https://librechat.k3s.internal"
