#!/usr/bin/env bash
# Inject the central LAN names (network/lan-hosts) into /etc/hosts on every
# non-NixOS machine: the Proxmox host, the Debian LXCs, and the k3s VM. The NixOS
# guests get the same file declaratively via networking.extraHosts, so they're
# skipped here. Run on the Proxmox host (uses pct + qm). Idempotent: it replaces
# a marked block, so re-running after editing network/lan-hosts just refreshes it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTS_FILE="$REPO_ROOT/network/lan-hosts"

# Debian LXCs (pihole, playground-debian) by vmid.
cts=( "pihole=101" "playground-debian=108" )
# VMs (k3s) by vmid; needs the qemu guest agent (enabled in tofu/k3s.tf).
vms=( "k3s=104" )

# The remote applier: strip any old block, append a fresh one. Reads the new
# entries from /tmp/lan-hosts on the target. Kept as a single-quoted string so
# nothing here expands locally; it runs verbatim on each machine.
# shellcheck disable=SC2016
applier='
set -euo pipefail
b="# >>> homelab-core lan-hosts >>>"; e="# <<< homelab-core lan-hosts <<<"
t="$(mktemp)"
sed "/$b/,/$e/d" /etc/hosts > "$t"
{ echo "$b"; cat /tmp/lan-hosts; echo "$e"; } >> "$t"
install -m 644 "$t" /etc/hosts
rm -f "$t" /tmp/lan-hosts
'

echo "== proxmox host =="
cp "$HOSTS_FILE" /tmp/lan-hosts
bash -c "$applier"

for entry in "${cts[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (CT $vmid) =="
  # on-demand CTs (playground-debian) may be stopped; skip rather than fail.
  if ! pct status "$vmid" 2>/dev/null | grep -q running; then
    echo "  not running, skipping (re-run this once it's up)"
    continue
  fi
  pct push "$vmid" "$HOSTS_FILE" /tmp/lan-hosts
  pct exec "$vmid" -- bash -c "$applier"
done

for entry in "${vms[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (VM $vmid) =="
  if ! qm guest exec "$vmid" -- true >/dev/null 2>&1; then
    echo "  guest agent not reachable, skipping (names work once it's up; re-run this)"
    continue
  fi
  # Hand the file over base64-encoded (no file-push over the guest agent), then
  # run the same applier in the guest.
  data="$(base64 -w0 "$HOSTS_FILE")"
  qm guest exec "$vmid" -- bash -c "echo $data | base64 -d > /tmp/lan-hosts; $applier" >/dev/null
done

echo "lan-hosts injected."
