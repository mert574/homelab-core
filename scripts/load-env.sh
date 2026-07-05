#!/usr/bin/env bash
# Load the homelab secrets into the current shell: SOPS_AGE_KEY_FILE plus every
# var in secrets/homelab.enc.env (TF_VAR_*, GIT_HTTP_TOKEN, PIHOLE_WEBPASSWORD, ...).
#
# SOURCE it, don't run it:   source scripts/load-env.sh
#
# The homelab scripts source this themselves, so you only need it by hand for
# ad-hoc commands like `tofu -chdir=tofu apply`.
#
# The .enc.env is a plain dotenv (KEY=value, no quotes) so sops-nix reads clean
# values inside the guests. That means we must NOT `eval` it here (a value with
# spaces, like the SSH key, would break) - parse line by line instead.
__r="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/root/.config/sops/age/keys.txt}"
while IFS='=' read -r __k __v; do
  case "$__k" in '' | \#*) continue ;; esac
  export "$__k=$__v"
done < <(sops -d --output-type dotenv "$__r/secrets/homelab.enc.env")
unset __r __k __v
