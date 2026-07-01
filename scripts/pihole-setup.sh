#!/usr/bin/env bash
# Headless Pi-hole install + config on the pihole CT (101). Run on the Proxmox
# host. Idempotent: installs Pi-hole if missing, then (re)sets the admin password,
# the .internal local DNS records (from network/lan-hosts), and turns off FTL's
# NTP clock-setting (which an unprivileged LXC can't do).
#
# Needs PIHOLE_WEBPASSWORD in the environment (it's in the sops env):
#   export SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt
#   set -a; eval "$(sops -d secrets/homelab.enc.env)"; set +a
#   ./scripts/pihole-setup.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CT=101
: "${PIHOLE_WEBPASSWORD:?set PIHOLE_WEBPASSWORD (from the sops env)}"

pct status "$CT" | grep -q running || { pct start "$CT"; sleep 5; }

# dns.hosts array from lan-hosts: one "IP name" per hostname (split multi-name lines).
records="$(awk 'NF && $1 !~ /^#/ {
  for (i=2;i<=NF;i++) { if ($i ~ /^#/) break; printf "%s\"%s %s\"", (c++?",":""), $1, $i }
}' "$REPO_ROOT/network/lan-hosts")"

pct exec "$CT" -- env PIHOLE_WEBPASSWORD="$PIHOLE_WEBPASSWORD" DNS_HOSTS="[$records]" bash -s <<'INNER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/bin:$PATH"

if ! command -v pihole >/dev/null 2>&1; then
  apt-get update
  apt-get install -y curl ca-certificates
  install -d -m 755 /etc/pihole
  cat > /etc/pihole/setupVars.conf <<CONF
PIHOLE_INTERFACE=eth0
PIHOLE_DNS_1=1.1.1.1
PIHOLE_DNS_2=8.8.8.8
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
DNSMASQ_LISTENING=local
BLOCKING_ENABLED=true
CONF
  curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended
fi

# admin password (v6 uses setpassword; older uses -a -p)
pihole setpassword "$PIHOLE_WEBPASSWORD" 2>/dev/null || pihole -a -p "$PIHOLE_WEBPASSWORD" 2>/dev/null || true
# .internal local DNS records
pihole-FTL --config dns.hosts "$DNS_HOSTS" || true
# an unprivileged LXC can't set the clock; stop FTL trying
pihole-FTL --config ntp.sync.active false || true
pihole reloaddns 2>/dev/null || systemctl restart pihole-FTL
INNER

echo "pihole set up headless: http://192.168.178.101/admin"
