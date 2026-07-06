#!/usr/bin/env bash
# One-time install: copies the homelab-auto-apply unit + timer onto the
# Proxmox host and starts it. After this runs once, tofu reconciles itself on
# a schedule forever -- no one ever needs to run `tofu apply` by hand again.
# Run on the Proxmox host as root.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 644 "$HERE/homelab-auto-apply.service" /etc/systemd/system/homelab-auto-apply.service
install -m 644 "$HERE/homelab-auto-apply.timer" /etc/systemd/system/homelab-auto-apply.timer
systemctl daemon-reload
systemctl enable --now homelab-auto-apply.timer

echo "installed. check status with: systemctl status homelab-auto-apply.timer"
echo "check logs with: journalctl -u homelab-auto-apply.service -f"
