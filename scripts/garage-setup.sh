#!/usr/bin/env bash
# Set up Garage from code: assign the single-node layout, create the nix-cache
# bucket (served read-only over the web port for the Nix substituter) and import
# the CI write key. Run by the garage-setup systemd service inside the garage
# LXC, idempotent so it re-runs safely on every boot. garage/grep/awk come from
# the service's PATH; secrets are the sops-nix files under /run/secrets.
set -euo pipefail

GARAGE_RPC_SECRET="$(cat /run/secrets/GARAGE_RPC_SECRET)"
export GARAGE_RPC_SECRET
g() { garage -h 127.0.0.1:3901 "$@"; }

# Wait until the local node answers RPC before configuring it.
until g status >/dev/null 2>&1; do sleep 1; done

# Single-node layout: give this node a role once, then apply the new version.
node="$(g node id -q | cut -d@ -f1)"
if ! g layout show | grep -q "$node"; then
  g layout assign -z home -c 200G "$node"
  ver="$(g layout show | awk -F'version ' '/version/{print $2 + 0; exit}')"
  g layout apply --version "$((ver + 1))"
fi

ensure_site() {
  # bucket + global alias (the Host the web port matches) + public website
  g bucket list | grep -qw "$1" || g bucket create "$1"
  g bucket alias "$1" "$2" >/dev/null 2>&1 || true
  g bucket website --allow "$1" >/dev/null
}
ensure_site nix-cache nix-cache.garage.internal
# Pulse frontends: static buckets served by Host over the web port. The Gateway
# (app) / cloudflared route here; assets are pushed by CI (the write key below).
ensure_site pulse-app app.pulsepager.com
ensure_site pulse-docs pulsepager.com

# CI write key, imported from sops so it survives rebuilds and matches the GitHub
# secret the push job uses. Read stays anonymous over the web port.
kid="$(cat /run/secrets/NIX_CACHE_S3_ACCESS_KEY)"
ksec="$(cat /run/secrets/NIX_CACHE_S3_SECRET_KEY)"
g key list | grep -q "$kid" || g key import -n nix-cache "$kid" "$ksec" --yes
g bucket allow --read --write nix-cache --key nix-cache
