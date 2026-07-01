#!/usr/bin/env bash
# Teach the Proxmox host and the Debian guests about the xterm-ghostty terminfo,
# so shelling in from Ghostty doesn't spew "unknown terminal" from tput. Run on
# the Proxmox host.
#
# NixOS guests are handled declaratively instead (environment.enableAllTerminfo
# in nix/modules/base.nix), so they're not touched here.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/xterm-ghostty.terminfo"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

# Debian LXCs (vmid) and Debian VMs (vmid).
CTS=( "pihole=101" "playground-debian=108" )
VMS=( "k3s=104" )

echo "== proxmox host =="
command -v tic >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq ncurses-bin; }
tic -x "$SRC"
echo "  installed"

for entry in "${CTS[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (CT $vmid) =="
  if ! pct status "$vmid" 2>/dev/null | grep -q running; then
    echo "  not running, skipping (re-run once it's up)"; continue
  fi
  pct exec "$vmid" -- bash -c 'command -v tic >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq ncurses-bin; }'
  pct push "$vmid" "$SRC" /tmp/xterm-ghostty.terminfo
  pct exec "$vmid" -- bash -c 'tic -x /tmp/xterm-ghostty.terminfo && rm -f /tmp/xterm-ghostty.terminfo'
  echo "  installed"
done

for entry in "${VMS[@]}"; do
  name="${entry%%=*}"; vmid="${entry#*=}"
  echo "== $name (VM $vmid) =="
  if ! qm guest exec "$vmid" -- true >/dev/null 2>&1; then
    echo "  guest agent not reachable, skipping (re-run once it's up)"; continue
  fi
  b64="$(base64 -w0 "$SRC")"
  qm guest exec "$vmid" -- bash -c \
    "command -v tic >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq ncurses-bin; }; echo $b64 | base64 -d > /tmp/g.terminfo; tic -x /tmp/g.terminfo; rm -f /tmp/g.terminfo" >/dev/null
  echo "  installed"
done

echo "done. new shells (TERM=xterm-ghostty) will resolve on these boxes."
