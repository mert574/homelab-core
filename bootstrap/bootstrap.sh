#!/usr/bin/env bash
# Run once after SSHing into a freshly installed Proxmox host.
#
#   git clone https://github.com/mert574/homelab-core && cd homelab-core
#   ./bootstrap/bootstrap.sh
#
# It takes the age private key, installs it where sops looks, checks it can
# decrypt the repo's secrets, sets up the host network, and applies Layer 2
# (tofu). The NixOS hosts and Layer 3 run off-host afterwards (see DEPLOY.md).
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

  # Isolated vmbr1 bridge for the ai box (must exist before that container boots).
  bash "$REPO_ROOT/bootstrap/host-network/install.sh"

  # Layer 2: create the Proxmox guests.
  tofu -chdir="$REPO_ROOT/tofu" init -input=false
  tofu -chdir="$REPO_ROOT/tofu" apply -auto-approve

  # The rest runs off the Proxmox host (it has no nix / cluster access yet):
  echo "Layer 2 applied. Remaining steps (see DEPLOY.md):" >&2
  echo "  - NixOS hosts, from a machine with nix:" >&2
  echo "      nixos-rebuild switch --flake $REPO_ROOT/nix#<host> --target-host root@<ip>" >&2
  echo "      (postgres, cloudflared, garage, media, admin, ai, playground)" >&2
  echo "  - Layer 3: cluster/bootstrap/install.sh with KUBECONFIG from the k3s VM" >&2
}

main() {
  install_age_key
  verify_decrypt

  # tofu apply is long; wrap it in systemd-run if you want to disconnect mid-run.
  run_pipeline
  echo "done." >&2
}

main "$@"
