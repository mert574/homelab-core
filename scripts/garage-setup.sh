#!/usr/bin/env bash
# Set up Garage from code: assign the single-node layout, create the nix-cache
# bucket (served read-only over the web port for the Nix substituter) and import
# the CI write key. Run by the garage-setup systemd service inside the garage
# LXC, idempotent so it re-runs safely on every boot. garage/grep/awk come from
# the service's PATH; secrets come from the environment (the service loads
# /run/garage/env, produced by garage-secrets.service from the sops env — see
# garage.nix for why we can't use per-key sops secrets on a dotenv file).
set -euo pipefail

: "${GARAGE_RPC_SECRET:?not set — expected from garage-secrets.service EnvironmentFile}"
export GARAGE_RPC_SECRET
# No -h: run locally, garage reads /etc/garage.toml for the node's rpc_public_addr
# and identity. (This garage's -h wants <node-id>@host:port, not a bare host:port.)
g() { garage "$@"; }

# Wait until the local node answers RPC before configuring it. Bounded, so a
# broken garage makes this unit fail cleanly instead of hanging the boot/switch
# forever (an unbounded `until` here once stalled a whole nixos-rebuild).
for _ in $(seq 1 60); do
  g status >/dev/null 2>&1 && break
  sleep 1
done
g status >/dev/null 2>&1 || { echo "garage-setup: node not answering RPC after 60s" >&2; exit 1; }

# NB: never pipe garage straight into `grep -q` / `awk … exit` — this garage
# (v1.3.x) panics when its stdout pipe is closed early (broken pipe). So capture
# its output with $(...) first, then match with a here-string: garage has already
# finished writing, and each match is a single command with a clean exit status.

# Single-node layout: give this node a role once, then apply it. Idempotency
# keys off the *applied* layout version — 0 means no role has been applied yet
# (a merely staged role still reads as version 0), so this converges whether the
# node is fresh or left with a half-staged layout from an earlier run.
node="$(g node id -q | cut -d@ -f1)"
ver="$(awk -F': ' '/Current cluster layout version/{print $2 + 0; exit}' <<<"$(g layout show)")"
if [ "${ver:-0}" -eq 0 ]; then
  g layout assign -z home -c 200G "$node"
  g layout apply --version "$((ver + 1))"
fi

ensure_site() {
  # bucket + global alias (the Host the web port matches) + public website
  grep -qw "$1" <<<"$(g bucket list)" || g bucket create "$1"
  g bucket alias "$1" "$2" >/dev/null 2>&1 || true
  g bucket website --allow "$1" >/dev/null
}
ensure_site nix-cache nix-cache.garage.internal
# Pulse frontends: static buckets served by Host over the web port. The Gateway
# (app) / cloudflared route here; assets are pushed by CI (the write key below).
ensure_site pulse-app app.pulsepager.com
ensure_site pulse-docs pulsepager.com

# Personal site (blog + portfolio, repo mert574/blog). Served at the apex; add a
# second global alias so www hits the same bucket. cloudflared routes both here.
ensure_site mert574.dev mert574.dev
g bucket alias mert574.dev www.mert574.dev >/dev/null 2>&1 || true

# CI write key, imported from sops so it survives rebuilds and matches the GitHub
# secret the push job uses. Read stays anonymous over the web port.
kid="${NIX_CACHE_S3_ACCESS_KEY:?not set — expected from garage-secrets.service EnvironmentFile}"
ksec="${NIX_CACHE_S3_SECRET_KEY:?not set — expected from garage-secrets.service EnvironmentFile}"
grep -q "$kid" <<<"$(g key list)" || g key import -n nix-cache "$kid" "$ksec" --yes
g bucket allow --read --write nix-cache --key nix-cache

# Blog CI write key, same import-from-sops story as nix-cache above. The blog repo
# (mert574/blog) pushes the built site with this key; read stays anonymous.
bkid="${BLOG_S3_ACCESS_KEY:?not set, expected from garage-secrets.service EnvironmentFile}"
bksec="${BLOG_S3_SECRET_KEY:?not set, expected from garage-secrets.service EnvironmentFile}"
grep -q "$bkid" <<<"$(g key list)" || g key import -n blog "$bkid" "$bksec" --yes
g bucket allow --read --write mert574.dev --key blog
