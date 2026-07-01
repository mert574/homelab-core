#!/usr/bin/env bash
# Run on a freshly installed Proxmox host. first-boot.sh calls this unattended
# (age key on stdin), or run it by hand:
#
#   git clone https://github.com/mert574/homelab-core && cd homelab-core
#   ./bootstrap/bootstrap.sh           (paste key, then Ctrl-D)
#   ./bootstrap/bootstrap.sh < age.key (piped)
#
# It installs the tools a stock Proxmox lacks, installs the age key where sops
# looks, checks it can decrypt the repo's secrets, sets up root's self-SSH (the
# tofu provider needs it), makes sure the guest templates are on the node, brings
# up the host network, and applies Layer 2 (tofu) + the NixOS guests.
#
# The key is read from a silent prompt (or piped stdin), never a command
# argument, so it does not land in shell history or `ps`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGE_KEY_DIR="/root/.config/sops/age"
AGE_KEY_FILE="${AGE_KEY_DIR}/keys.txt"
SECRETS_FILE="${REPO_ROOT}/secrets/homelab.enc.env"

# Pinned tool versions (a stock Proxmox has none of these).
SOPS_VERSION="3.13.2"
TOFU_VERSION="1.12.3"
# Node-local SSH key the bpg provider uses to reach the node (itself).
NODE_SSH_KEY="/root/.ssh/id_ed25519_pve"
# Templates the guests are built from.
DEBIAN_CT_TEMPLATE="debian-13-standard_13.1-1_amd64.tar.zst"
NIXOS_CT_TEMPLATE="/var/lib/vz/template/cache/nixos-proxmox-lxc.tar.xz"

# --- tooling -----------------------------------------------------------------
ensure_tools() {
  export DEBIAN_FRONTEND=noninteractive
  local need_apt=()
  command -v git >/dev/null 2>&1 || need_apt+=(git)
  command -v age >/dev/null 2>&1 || need_apt+=(age)      # ships age-keygen too
  command -v curl >/dev/null 2>&1 || need_apt+=(curl)
  if [ "${#need_apt[@]}" -gt 0 ]; then
    apt-get update -qq
    apt-get install -y -qq "${need_apt[@]}"
  fi

  if ! command -v sops >/dev/null 2>&1; then
    echo "installing sops ${SOPS_VERSION}" >&2
    curl -fsSL -o /usr/local/bin/sops \
      "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64"
    chmod +x /usr/local/bin/sops
  fi

  if ! command -v tofu >/dev/null 2>&1; then
    echo "installing opentofu ${TOFU_VERSION}" >&2
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/tofu.zip" \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.zip"
    ( cd "$tmp" && unzip -q tofu.zip tofu && install -m755 tofu /usr/local/bin/tofu )
    rm -rf "$tmp"
  fi
}

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

# --- self-SSH for the tofu provider ------------------------------------------
# bpg SSHes to the node for snippet uploads and the k3s VM's cloud-image import.
# tofu runs on the node, so root SSHes to itself with this dedicated key.
ensure_node_ssh() {
  install -d -m 700 /root/.ssh
  [ -f "$NODE_SSH_KEY" ] || ssh-keygen -t ed25519 -N '' -q -f "$NODE_SSH_KEY"
  local pub; pub="$(cat "${NODE_SSH_KEY}.pub")"
  if ! grep -qF "$pub" /root/.ssh/authorized_keys 2>/dev/null; then
    echo "$pub" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
  fi
  # Pre-trust the node so the provider's SSH doesn't stall on host-key prompts.
  ssh-keyscan -H 127.0.0.1 192.168.178.100 2>/dev/null >> /root/.ssh/known_hosts || true
  sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts 2>/dev/null || true
}

# --- guest templates ---------------------------------------------------------
ensure_templates() {
  # Debian LXC (pihole). pveam skips the download if it's already present.
  if ! pveam list local 2>/dev/null | grep -q "$DEBIAN_CT_TEMPLATE"; then
    pveam update
    pveam download local "$DEBIAN_CT_TEMPLATE"
  fi

  # NixOS LXC (every NixOS guest). Proxmox ships none, so build one with
  # nixos-generators. Needs nix; install it single-user if missing.
  if [ ! -f "$NIXOS_CT_TEMPLATE" ]; then
    if ! command -v nix >/dev/null 2>&1; then
      echo "installing nix (to build the NixOS LXC template)" >&2
      curl -fsSL https://nixos.org/nix/install | sh -s -- --no-daemon --yes
    fi
    # shellcheck disable=SC1091
    . /root/.nix-profile/etc/profile.d/nix.sh 2>/dev/null || . "$HOME/.nix-profile/etc/profile.d/nix.sh"
    local out
    nix --extra-experimental-features 'nix-command flakes' \
      run github:nix-community/nixos-generators -- -f proxmox-lxc -o /tmp/nixos-lxc-result
    out="$(readlink -f /tmp/nixos-lxc-result/tarball/*.tar.xz 2>/dev/null || readlink -f /tmp/nixos-lxc-result/*.tar.xz)"
    install -m644 "$out" "$NIXOS_CT_TEMPLATE"
    rm -rf /tmp/nixos-lxc-result
  fi
}

run_pipeline() {
  # Load secrets as env vars (TF_VAR_* go straight into OpenTofu).
  set -a; eval "$(sops --decrypt "$SECRETS_FILE")"; set +a

  # Isolated vmbr1 bridge for the ai box (must exist before that container boots).
  bash "$REPO_ROOT/bootstrap/host-network/install.sh"

  # Layer 2: create the Proxmox guests.
  tofu -chdir="$REPO_ROOT/tofu" init -input=false
  tofu -chdir="$REPO_ROOT/tofu" apply -auto-approve

  # Let the guests boot, then spread the central LAN names to the non-NixOS
  # machines (NixOS guests get them from their own config in the next step).
  sleep 10
  bash "$REPO_ROOT/scripts/inject-hosts.sh"

  # Configure every NixOS guest (nixos-rebuild inside each via pct).
  bash "$REPO_ROOT/scripts/apply-nixos.sh"

  # Layer 3 still runs once k3s is up and we have its kubeconfig:
  echo "Guests configured. Next: cluster/bootstrap/install.sh with KUBECONFIG" >&2
  echo "from the k3s VM (see DEPLOY.md)." >&2
}

main() {
  ensure_tools
  install_age_key
  verify_decrypt
  ensure_node_ssh
  ensure_templates

  # tofu apply is long; wrap it in systemd-run if you want to disconnect mid-run.
  run_pipeline
  echo "done." >&2
}

main "$@"
