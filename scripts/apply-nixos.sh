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
# cloudflared and media are left out by default: they read sops files that aren't
# in the repo yet (secrets/cloudflared.creds.enc, mullvad.wg.enc, digarr.env.enc)
# and need external creds (Cloudflare tunnel, Mullvad). A missing sopsFile fails
# the nixos-rebuild at eval, so we skip them until those are set up. Once they are,
# run with HOMELAB_ALL_HOSTS=1 to include them.
hosts=(
  "postgres=102" "admin=105" "ai=106" "playground=107" "garage=109"
)
if [ "${HOMELAB_ALL_HOSTS:-0}" = "1" ]; then
  hosts+=( "cloudflared=103" "media=110" )
fi

archive=/tmp/homelab-core.tgz
tar czf "$archive" -C "$REPO_ROOT" --exclude=.git --exclude=tofu/.terraform .

apply() {
  local name="$1" vmid="$2"
  echo "== $name (CT $vmid) =="
  pct exec "$vmid" -- install -d -m 700 /var/lib/sops-nix
  pct push "$vmid" "$AGE_KEY" /var/lib/sops-nix/key.txt --perms 600
  pct push "$vmid" "$archive" /root/homelab-core.tgz
  pct exec "$vmid" -- bash -c \
    'rm -rf /root/homelab-core && mkdir -p /root/homelab-core && tar xzf /root/homelab-core.tgz -C /root/homelab-core'
  pct exec "$vmid" -- nixos-rebuild switch \
    --flake "/root/homelab-core/nix#$name" \
    --extra-experimental-features 'nix-command flakes'
}

for entry in "${hosts[@]}"; do
  apply "${entry%%=*}" "${entry#*=}"
done
echo "all NixOS hosts applied."
