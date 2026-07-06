#!/usr/bin/env bash
# Idempotent upsert of a single login item into the self-hosted Vaultwarden
# vault (pw.mert574.dev) via the Bitwarden CLI. Used to mirror generated
# credentials (e.g. app admin passwords) somewhere human-browsable, while
# sops stays the actual source of truth these scripts read from. Fully
# self-contained: callers just need SOPS_AGE_KEY_FILE set, same as any other
# script in this repo that reads the sops env -- no need to pre-export
# Vaultwarden's own creds.
#
# Usage: vaultwarden-upsert.sh <item-name> <username> <password> [url...]
# Any number of trailing URLs are all attached to the item (e.g. an app's
# internal and public hostnames both), so Bitwarden's URL-match autofill works
# from either.
#
# Everything this script touches -- both writes and the search used to find an
# existing item to update -- is scoped to the "homelab" folder. It will never
# look at or modify items outside that folder, even if a name collides.
set -euo pipefail
: "${SOPS_AGE_KEY_FILE:?}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
name="$1" username="$2" password="$3"; shift 3
urls_json="$(printf '%s\n' "$@" | jq -R . | jq -sc '[.[] | {uri: .}]')"
folder_name="homelab"

# VAULTWARDEN_BW_CLIENT_ID / VAULTWARDEN_BW_CLIENT_SECRET (device auth, from
# Vaultwarden's My Account -> API Key) and VAULTWARDEN_MASTER_PASSWORD (to
# derive the vault decryption key -- the API key alone can't read/write item
# contents) live in the sops env, same as every other homelab-wide secret.
homelab_env="$(sops -d --input-type dotenv --output-type dotenv "$REPO_ROOT/secrets/homelab.enc.env")"
get_secret() { echo "$homelab_env" | grep -m1 "^$1=" | sed -E 's/^[A-Za-z_]+="?(.*[^"])"?$/\1/'; }
VAULTWARDEN_BW_CLIENT_ID="$(get_secret VAULTWARDEN_BW_CLIENT_ID)"
VAULTWARDEN_BW_CLIENT_SECRET="$(get_secret VAULTWARDEN_BW_CLIENT_SECRET)"
VAULTWARDEN_MASTER_PASSWORD="$(get_secret VAULTWARDEN_MASTER_PASSWORD)"
export VAULTWARDEN_MASTER_PASSWORD
: "${VAULTWARDEN_BW_CLIENT_ID:?}" "${VAULTWARDEN_BW_CLIENT_SECRET:?}" "${VAULTWARDEN_MASTER_PASSWORD:?}"

# skip re-config/re-login if a session from an earlier run is already active
# on this box ("bw config server" while logged in errors: logout required)
if ! bw status | jq -e '.status != "unauthenticated"' >/dev/null 2>&1; then
  bw config server https://pw.mert574.dev >/dev/null
  BW_CLIENTID="$VAULTWARDEN_BW_CLIENT_ID" BW_CLIENTSECRET="$VAULTWARDEN_BW_CLIENT_SECRET" \
    bw login --apikey >/dev/null
fi

session="$(bw unlock --passwordenv VAULTWARDEN_MASTER_PASSWORD --raw)"
bw sync --session "$session" >/dev/null

folder_id="$(bw list folders --session "$session" \
  | jq -r --arg n "$folder_name" '.[] | select(.name == $n) | .id')"
[ -n "$folder_id" ] || { echo "vaultwarden-upsert: no \"$folder_name\" folder -- create it first" >&2; exit 1; }

existing_id="$(bw list items --search "$name" --session "$session" \
  | jq -r --arg n "$name" --arg f "$folder_id" \
      '[.[] | select(.name == $n and .folderId == $f)][0].id // empty')"

if [ -n "$existing_id" ]; then
  bw get item "$existing_id" --session "$session" \
    | jq --arg u "$username" --arg p "$password" --argjson uris "$urls_json" \
        '.login.username = $u | .login.password = $p
         | if ($uris | length) > 0 then .login.uris = $uris else . end' \
    | bw encode \
    | bw edit item "$existing_id" --session "$session" >/dev/null
  echo "vaultwarden: updated \"$name\" (folder: $folder_name)"
else
  bw get template item --session "$session" \
    | jq --arg n "$name" --arg u "$username" --arg p "$password" --argjson uris "$urls_json" --arg f "$folder_id" \
        '.name = $n | .type = 1 | .folderId = $f
         | .login = ({username: $u, password: $p}
             + (if ($uris | length) > 0 then {uris: $uris} else {} end))' \
    | bw encode \
    | bw create item --session "$session" >/dev/null
  echo "vaultwarden: created \"$name\" (folder: $folder_name)"
fi

bw lock --session "$session" >/dev/null 2>&1 || true
