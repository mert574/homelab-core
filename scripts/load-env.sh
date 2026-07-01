#!/usr/bin/env bash
# Load the homelab secrets into the current shell: SOPS_AGE_KEY_FILE plus every
# var in secrets/homelab.enc.env (TF_VAR_*, GIT_HTTP_TOKEN, PIHOLE_WEBPASSWORD, ...).
#
# SOURCE it, don't run it:   source scripts/load-env.sh
#
# The homelab scripts source this themselves, so you only need it by hand for
# ad-hoc commands like `tofu -chdir=tofu apply`.
__r="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-/root/.config/sops/age/keys.txt}"
set -a
eval "$(sops -d "$__r/secrets/homelab.enc.env")"
set +a
unset __r
