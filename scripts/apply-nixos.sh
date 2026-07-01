#!/usr/bin/env bash
# Turn each base-NixOS guest into its real host by running nixos-rebuild inside it.
# Run on the Proxmox host: it uses `pct`, so no SSH into the base image and no nix
# on the host are needed. Each guest builds its own config locally.
#
# Needs the master age key on this host (default path below) so sops-nix can
# decrypt, and the guests already created (tofu apply) and booted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGE_KEY="${AGE_KEY:-/root/.config/sops/age/keys.txt}"

# host = container vmid (NixOS LXCs only; not k3s (a VM) or playground-debian)
#
# All NixOS guests. cloudflared and media both have their sops files now
# (cloudflared.creds.enc, mullvad.wg.enc); digarr inside media is disabled until
# its env exists (see media.nix).
hosts=(
  "postgres=102" "cloudflared=103" "admin=105" "ai=106"
  "playground=107" "garage=109" "media=110"
)

archive=/tmp/homelab-core.tgz
tar czf "$archive" -C "$REPO_ROOT" --exclude=.git --exclude=tofu/.terraform .

apply() {
  local name="$1" vmid="$2"
  echo "== $name (CT $vmid) =="
  # Some guests are started=false (on-demand). Start them to apply, and give the
  # network a moment so nixos-rebuild can fetch. Restore the stopped ones after.
  local was_stopped=0
  if ! pct status "$vmid" | grep -q running; then
    was_stopped=1
    pct start "$vmid"
    sleep 15
  fi
  pct exec "$vmid" -- install -d -m 700 /var/lib/sops-nix
  pct push "$vmid" "$AGE_KEY" /var/lib/sops-nix/key.txt --perms 600
  pct push "$vmid" "$archive" /root/homelab-core.tgz
  pct exec "$vmid" -- bash -c \
    'rm -rf /root/homelab-core && mkdir -p /root/homelab-core && tar xzf /root/homelab-core.tgz -C /root/homelab-core'
  pct exec "$vmid" -- nixos-rebuild switch \
    --flake "/root/homelab-core/nix#$name" \
    --extra-experimental-features 'nix-command flakes'
  # put on-demand guests back to sleep
  [ "$was_stopped" = 1 ] && pct stop "$vmid" || true
}

# Optional args = a subset of host names to apply (e.g. `apply-nixos.sh cloudflared`).
# No args = all of them.
want=( "$@" )
in_want() {
  [ "${#want[@]}" -eq 0 ] && return 0
  local w; for w in "${want[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

for entry in "${hosts[@]}"; do
  name="${entry%%=*}"
  in_want "$name" || continue
  apply "$name" "${entry#*=}"
done
echo "NixOS hosts applied."
