#!/usr/bin/env bash
# Run once after SSHing into a freshly installed Proxmox host.
#
#   git clone https://github.com/mert574/homelab-core && cd homelab-core
#   ./bootstrap/bootstrap.sh
#
# It takes the age private key, installs it where sops looks, checks it can
# decrypt the repo's secrets, then launches Layers 2 and 3 detached so you can
# disconnect right away.
#
# The key is read from a silent prompt (or piped stdin), never a command
# argument, so it does not land in shell history or `ps`.
#
#   interactive:  ./bootstrap/bootstrap.sh           (paste key, then Ctrl-D)
#   piped:        ./bootstrap/bootstrap.sh < age.key

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGE_KEY_DIR="/root/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"
SECRETS_FILE="${REPO_ROOT}/secrets/homelab.enc.env"

install_age_key() {
  if [ -t 0 ]; then
    echo "Paste the age private key, then press Ctrl-D:" >&2
  fi
  install -d -m 700 "$AGE_KEY_DIR"
  ( umask 077; cat > "$AGE_KEY_FILE" )
  chmod 600 "$AGE_KEY_FILE"
  echo "age key installed at $AGE_KEY_FILE" >&2
}

verify_decrypt() {
  export SOPS_AGE_KEY_FILE="$AGE_KEY_FILE"
  if ! sops --decrypt "$SECRETS_FILE" >/dev/null 2>&1; then
    echo "ERROR: cannot decrypt $SECRETS_FILE with this key" >&2
    exit 1
  fi
  echo "secrets decrypt OK" >&2
}

run_pipeline() {
  # Load secrets as env vars (TF_VAR_* go straight into OpenTofu).
  set -a; eval "$(sops --decrypt "$SECRETS_FILE")"; set +a

  # TODO(Layer 2): tofu -chdir="$REPO_ROOT/tofu" init -input=false
  #                tofu -chdir="$REPO_ROOT/tofu" apply -auto-approve
  # TODO(Layer 3): install Argo CD on the k3s VM, install the age key into the
  #                cluster (for KSOPS/sops-operator), apply the root app-of-apps.
  echo "pipeline not wired yet (Layers 2 and 3 are still being built)" >&2
}

main() {
  install_age_key
  verify_decrypt

  # Launch the long-running pipeline detached so closing SSH does not kill it.
  # Once Layers 2 and 3 are wired, swap the inline call for the systemd-run line.
  #   systemd-run --unit=homelab-bootstrap --collect bash -c 'run_pipeline'
  run_pipeline
  echo "done. you can disconnect." >&2
}

main "$@"
