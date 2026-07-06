#!/usr/bin/env bash
# Create the activepieces namespace + activepieces-secrets, then bootstrap the
# platform admin account headlessly (no manual signup-screen step) and mirror
# its password into Vaultwarden. Idempotent -- safe to re-run.
#
# Run with KUBECONFIG set and the sops env available:
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   cluster/apps/activepieces/create-secrets.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
: "${SOPS_AGE_KEY_FILE:?}"

kubectl create namespace activepieces --dry-run=client -o yaml | kubectl apply -f -

# the whole Activepieces env (its DSN already points at postgres.internal + the
# shared pulse redis). kubectl --from-env-file takes each value literally and
# does NOT strip dotenv quotes, so strip one layer of surrounding matched
# quotes before handing it to kubectl (same as pulse's create-secrets.sh).
env_plain="$(mktemp)"; trap 'rm -f "$env_plain"' EXIT
sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/activepieces.env.enc" \
  | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*)="(.*)"$/\1=\2/; s/^([A-Za-z_][A-Za-z0-9_]*)='"'"'(.*)'"'"'$/\1=\2/' \
  > "$env_plain"
kubectl -n activepieces create secret generic activepieces-secrets --from-env-file="$env_plain" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n activepieces rollout status deploy/activepieces --timeout=180s 2>/dev/null || true

# --- headless admin bootstrap ---
# read the admin creds straight from the still-quoted decrypted env (not the
# stripped copy above, just simpler to re-grep)
ap_env="$(sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/activepieces.env.enc")"
get() { echo "$ap_env" | grep -m1 "^$1=" | sed -E 's/^[A-Za-z_]+="?(.*[^"])"?$/\1/'; }
admin_email="$(get AP_ADMIN_EMAIL)"
admin_password="$(get AP_ADMIN_PASSWORD)"
admin_first="$(get AP_ADMIN_FIRST_NAME)"
admin_last="$(get AP_ADMIN_LAST_NAME)"

# hit the API through a transient port-forward, not the public hostname --
# avoids depending on the Cloudflare tunnel/DNS being up yet during bootstrap
pf_log="$(mktemp)"
kubectl -n activepieces port-forward svc/activepieces 18091:80 >"$pf_log" 2>&1 &
pf_pid=$!
trap 'kill "$pf_pid" 2>/dev/null; rm -f "$env_plain" "$pf_log"' EXIT
for _ in $(seq 1 20); do curl -sf http://127.0.0.1:18091/api/v1/health >/dev/null 2>&1 && break; sleep 1; done

signup_body="$(jq -n --arg e "$admin_email" --arg p "$admin_password" --arg f "$admin_first" --arg l "$admin_last" \
  '{email:$e, password:$p, firstName:$f, lastName:$l, trackEvents:false, newsLetter:false}')"
signup_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18091/api/v1/authentication/sign-up \
  -H "Content-Type: application/json" -d "$signup_body")"
if [ "$signup_code" = "200" ]; then
  echo "activepieces: admin account created ($admin_email)"
else
  echo "activepieces: admin sign-up skipped, already bootstrapped (HTTP $signup_code)"
fi

kill "$pf_pid" 2>/dev/null || true

# mirror the admin password into Vaultwarden (best-effort; sops stays the
# source of truth, so don't fail the whole bootstrap if Vaultwarden is down)
"$REPO_ROOT/scripts/vaultwarden-upsert.sh" "Activepieces admin" "$admin_email" "$admin_password" \
  "https://ap.k3s.internal" "https://ap.mert574.dev" || echo "activepieces: Vaultwarden mirror failed, continuing (sops still has it)"

echo "activepieces: namespace + activepieces-secrets created, admin bootstrapped."
