#!/usr/bin/env bash
# Install a systemd unit on every Debian guest that runs `apt update` + `apt
# upgrade` once per boot, after the network is up. Run on the Proxmox host.
#
# NixOS guests are intentionally left out: they have no apt and update via
# nixos-rebuild (scripts/apply-nixos.sh). This only covers the Debian family.
set -euo pipefail

# Debian LXCs (vmid) and Debian VMs (vmid).
CTS=( "pihole=101" "playground-debian=108" )
VMS=( "k3s=104" )

read -r -d '' UNIT <<'EOF' || true
[Unit]
Description=apt update and upgrade on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=DEBIAN_FRONTEND=noninteractive
ExecStart=/usr/bin/apt-get update
ExecStart=/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade

[Install]
WantedBy=multi-user.target
EOF

UNIT_PATH=/etc/systemd/system/apt-boot-upgrade.service

for entry in "${CTS[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (CT $vmid) =="
  if ! pct status "$vmid" 2>/dev/null | grep -q running; then
    echo "  not running, skipping (re-run once it's up)"; continue
  fi
  printf '%s\n' "$UNIT" | pct exec "$vmid" -- tee "$UNIT_PATH" >/dev/null
  pct exec "$vmid" -- systemctl enable apt-boot-upgrade.service
  echo "  enabled"
done

for entry in "${VMS[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (VM $vmid) =="
  if ! qm guest exec "$vmid" -- true >/dev/null 2>&1; then
    echo "  guest agent not reachable, skipping (re-run once it's up)"; continue
  fi
  b64="$(printf '%s\n' "$UNIT" | base64 -w0)"
  qm guest exec "$vmid" -- bash -c \
    "echo $b64 | base64 -d > $UNIT_PATH; systemctl enable apt-boot-upgrade.service" >/dev/null
  echo "  enabled"
done

echo "done. each Debian guest will apt update+upgrade on its next boot."
