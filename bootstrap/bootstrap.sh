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
# NixOS LXC template we build (Debian one is picked dynamically at runtime).
NIXOS_CT_TEMPLATE="/var/lib/vz/template/cache/nixos-proxmox-lxc.tar.xz"

# --- tooling -----------------------------------------------------------------
fix_pve_repos() {
  # A fresh Proxmox has the enterprise repos on, which 401 without a subscription
  # and break `apt-get update`. Turn them off and add the no-subscription repo.
  sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true
  local f
  for f in /etc/apt/sources.list.d/*enterprise*.sources /etc/apt/sources.list.d/ceph*.sources; do
    [ -e "$f" ] && mv "$f" "$f.disabled"
  done
  echo 'deb http://download.proxmox.com/debian/pve trixie pve-no-subscription' \
    > /etc/apt/sources.list.d/pve-no-subscription.list
}

ensure_tools() {
  export DEBIAN_FRONTEND=noninteractive
  fix_pve_repos
  local need_apt=()
  command -v git >/dev/null 2>&1 || need_apt+=(git)
  command -v age >/dev/null 2>&1 || need_apt+=(age)      # ships age-keygen too
  command -v curl >/dev/null 2>&1 || need_apt+=(curl)
  command -v unzip >/dev/null 2>&1 || need_apt+=(unzip)  # the tofu release is a zip
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
  # Read stdin fully first, so piping the key file into itself can't truncate it.
  local key; key="$(cat)"
  [ -n "$key" ] || { echo "no age key on stdin" >&2; exit 1; }
  install -d -m 700 "$AGE_KEY_DIR"
  ( umask 077; printf '%s\n' "$key" > "$AGE_KEY_FILE" )
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
  # The k3s VM's cloud-init is uploaded to `local` as a snippet, but fresh
  # Proxmox `local` doesn't allow the snippets content type. Enable it.
  pvesm set local --content vztmpl,iso,backup,snippets 2>/dev/null || true

  # Debian LXC (pihole, playground-debian). Detect whatever debian-13-standard is
  # current (no version hardcoded), download it, and write the exact volume id to a
  # tofu auto.tfvars, so a plain `tofu apply` uses the same value this script did.
  pveam update || true
  local deb_tmpl
  deb_tmpl="$(pveam available --section system 2>/dev/null | awk '/debian-13-standard/{print $NF}' | sort -V | tail -1)"
  if [ -n "$deb_tmpl" ]; then
    pveam list local 2>/dev/null | grep -q "$deb_tmpl" || pveam download local "$deb_tmpl"
    printf 'debian_ct_template = "local:vztmpl/%s"\n' "$deb_tmpl" \
      > "$REPO_ROOT/tofu/debian_template.auto.tfvars"
  fi

  # NixOS LXC (every NixOS guest). Proxmox ships none, so build one with
  # nixos-generators. Needs nix; the official installer can't do unattended-root
  # (no sudo, no nixbld group), so use the Determinate installer, which can.
  if [ ! -f "$NIXOS_CT_TEMPLATE" ]; then
    local nixbin=/nix/var/nix/profiles/default/bin/nix
    if ! command -v nix >/dev/null 2>&1 && [ ! -x "$nixbin" ]; then
      echo "installing nix (Determinate installer) to build the NixOS LXC template" >&2
      command -v xz >/dev/null 2>&1 || apt-get install -y -qq xz-utils
      curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
    fi
    command -v nix >/dev/null 2>&1 || export PATH="/nix/var/nix/profiles/default/bin:$PATH"
    # nixos-generators is deprecated (upstreamed). base.nix imports the nixpkgs
    # proxmox-lxc module, which exposes system.build.tarball, so build that
    # straight from the flake (admin has no sops deps, so it evals cleanly).
    nix build --extra-experimental-features 'nix-command flakes' \
      "$REPO_ROOT/nix#nixosConfigurations.admin.config.system.build.tarball" \
      -o /tmp/nixos-lxc-result
    local out
    out="$(find -L /tmp/nixos-lxc-result -name '*.tar.xz' | head -1)"
    [ -n "$out" ] || { echo "NixOS template build produced no tarball" >&2; exit 1; }
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

  # Headless Pi-hole install + config on the Debian CT (uses PIHOLE_WEBPASSWORD
  # from the sops env sourced above).
  bash "$REPO_ROOT/scripts/pihole-setup.sh"

  # Configure every NixOS guest (nixos-rebuild inside each via pct).
  bash "$REPO_ROOT/scripts/apply-nixos.sh"

  # Debian guests: boot-time apt upgrade + ghostty terminfo (best-effort).
  bash "$REPO_ROOT/scripts/apt-boot-upgrade.sh" || echo "apt-boot-upgrade had issues (non-fatal)" >&2
  bash "$REPO_ROOT/scripts/ghostty-terminfo.sh" || echo "ghostty-terminfo had issues (non-fatal)" >&2

  # Layer 3: bring up the cluster + Pulse. Non-fatal so a cluster hiccup doesn't
  # undo Layers 0-2 (they're already applied).
  bash "$REPO_ROOT/cluster/bootstrap/up.sh" || echo "Layer 3 needs attention (see above)" >&2
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
