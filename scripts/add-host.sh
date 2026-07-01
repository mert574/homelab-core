#!/usr/bin/env bash
# Add a host to the LAN name map (nix/lan-hosts, which feeds /etc/hosts on the
# guests via inject-hosts.sh + networking.extraHosts, and Pi-hole via
# pihole-setup.sh) AND to your ~/.ssh/config (so `ssh <name>` uses the homelab key).
#
#   ./scripts/add-host.sh ccflare.internal 192.168.178.111 [user]
#
# user defaults to root. After it edits nix/lan-hosts, commit + push so the guests
# and Pi-hole pick up the new name (re-run inject-hosts.sh / pihole-setup.sh).
set -euo pipefail

NAME="${1:?usage: add-host.sh <name> <ip> [user]}"
IP="${2:?usage: add-host.sh <name> <ip> [user]}"
LOGIN="${3:-root}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTS="$REPO_ROOT/nix/lan-hosts"
SSH_CFG="$HOME/.ssh/config"
KEY="$HOME/.ssh/homelab_ed25519"

# 1. LAN name map
if grep -qE "[[:space:]]${NAME}([[:space:]]|\$)" "$HOSTS"; then
  echo "$NAME already in $HOSTS"
else
  printf '%s  %s\n' "$IP" "$NAME" >> "$HOSTS"
  echo "added to nix/lan-hosts: $IP $NAME"
fi

# 2. ~/.ssh/config
if grep -qE "^Host .*(^| )${NAME}( |\$)" "$SSH_CFG" 2>/dev/null; then
  echo "$NAME already in $SSH_CFG"
else
  cat >> "$SSH_CFG" <<EOF

Host $NAME $IP
  HostName $IP
  User $LOGIN
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
  echo "added to ~/.ssh/config: Host $NAME ($LOGIN@$IP)"
fi

echo "done. commit + push nix/lan-hosts, then re-run inject-hosts.sh / pihole-setup.sh on the host."
