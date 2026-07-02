#!/usr/bin/env bash
# Make valid (throwaway-key) sops files for CI builds. sops-nix runs a build-time
# check that parses the sops files, so the empty placeholders that satisfy eval
# fail the actual build. These hold the key names each host reads; the check looks
# at structure and key names (cleartext in sops), it never decrypts. Needs age and
# sops on PATH (the workflow provides them via `nix shell`).
set -euo pipefail

keydir="${RUNNER_TEMP:-/tmp}"
age-keygen -o "$keydir/age.key" 2>/dev/null
pub="$(age-keygen -y "$keydir/age.key")"
printf 'creation_rules:\n  - age: %s\n' "$pub" > .sops.yaml
export SOPS_AGE_KEY_FILE="$keydir/age.key"

# dotenv bundle: every key the sops hosts read from homelab.enc.env
printf '%s\n' \
  PULSE_DB_PASSWORD=x \
  GARAGE_RPC_SECRET=x GARAGE_ADMIN_TOKEN=x \
  NIX_CACHE_S3_ACCESS_KEY=x NIX_CACHE_S3_SECRET_KEY=x > "$keydir/h.env"
sops -e --input-type dotenv --output-type dotenv "$keydir/h.env" > secrets/homelab.enc.env

# whole-file binary secrets
for f in cloudflared.creds mullvad.wg; do
  printf x | sops -e --input-type binary --output-type binary /dev/stdin > "secrets/$f.enc"
done

git add -A
