#!/usr/bin/env bash
# Run on the Proxmox host (root). Installs the isolated vmbr1 bridge that keeps
# the ai container off the LAN.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 644 "$HERE/99-homelab-ip-forward.conf" /etc/sysctl.d/99-homelab-ip-forward.conf
sysctl --system >/dev/null

install -m 644 "$HERE/vmbr1" /etc/network/interfaces.d/vmbr1
grep -qE '^\s*source\s+/etc/network/interfaces\.d/' /etc/network/interfaces \
  || echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces

ifreload -a 2>/dev/null || ifup vmbr1
echo "vmbr1 up. ai box can reach the internet but not the LAN."
