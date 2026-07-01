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

# Run a command inside a NixOS CT with the Nix profile on PATH. pct exec's default
# PATH has no /run/current-system/sw/bin, so bare ip/install/nixos-rebuild fail.
cx() {
  local id="$1"; shift
  pct exec "$id" -- /run/current-system/sw/bin/bash -c \
    "cd /; export PATH=/run/current-system/sw/bin:/run/wrappers/bin:\$PATH; $*"
}

apply() {
  local name="$1" vmid="$2"
  echo "== $name (CT $vmid) =="
  # Some guests are started=false (on-demand). Start them to apply; restore after.
  local was_stopped=0
  if ! pct status "$vmid" | grep -q running; then
    was_stopped=1
    pct start "$vmid"
    sleep 15
  fi
  # unmanaged ostype -> Proxmox doesn't set the IP inside, and the NixOS config
  # that does isn't active until the first rebuild (which needs the network). Set
  # the IP Proxmox already knows (net0) temporarily so the rebuild can fetch.
  local ip gw
  ip="$(pct config "$vmid" | grep -oP 'net0:.*ip=\K[0-9./]+' || true)"
  gw="$(pct config "$vmid" | grep -oP 'net0:.*gw=\K[0-9.]+' || true)"
  if [ -n "$ip" ]; then
    cx "$vmid" "ip addr replace $ip dev eth0; ip link set eth0 up" 2>/dev/null || true
    [ -n "$gw" ] && cx "$vmid" "ip route replace default via $gw" 2>/dev/null || true
    cx "$vmid" "rm -f /etc/resolv.conf; echo nameserver 1.1.1.1 > /etc/resolv.conf" 2>/dev/null || true
    # wait until DNS actually resolves before the rebuild fetches flake inputs,
    # else it races the network coming up and fails with "could not resolve host".
    for _ in $(seq 1 15); do
      cx "$vmid" "getent hosts github.com >/dev/null 2>&1" && break
      sleep 2
    done
  fi
  cx "$vmid" "install -d -m 700 /var/lib/sops-nix"
  pct push "$vmid" "$AGE_KEY" /var/lib/sops-nix/key.txt --perms 600
  pct push "$vmid" "$archive" /root/homelab-core.tgz
  cx "$vmid" "rm -rf /root/homelab-core && mkdir -p /root/homelab-core && tar xzf /root/homelab-core.tgz -C /root/homelab-core"
  # the new nixos-rebuild rejects --extra-experimental-features; enable via NIX_CONFIG.
  # --print-build-logs so the build isn't silent.
  cx "$vmid" "NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild switch --flake /root/homelab-core#$name --print-build-logs"
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
