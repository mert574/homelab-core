#!/usr/bin/env bash
# Fetch + build ccflare at a pinned commit into $HOME/src. Run by the ccflare-setup
# systemd service inside the ccflare LXC (nix/hosts/ccflare.nix), idempotent so it
# re-runs safely on every boot and is a no-op once already built at CCFLARE_REF.
# bun + git come from the service PATH; CCFLARE_REF + HOME from the unit env.
set -euo pipefail

REPO_URL="https://github.com/snipeship/ccflare"
SRC="$HOME/src"
STAMP="$HOME/.built-ref"
ref="${CCFLARE_REF:?CCFLARE_REF not set}"

# On the very first apply, this runs during nixos-rebuild activation while the
# network is still coming up, so DNS can briefly be empty (resolvconf races the
# switch). Wait for name resolution before we fetch, rather than hard-failing the
# unit — same guard apply-nixos.sh uses for the rebuild itself.
for _ in $(seq 1 30); do
  getent hosts github.com >/dev/null 2>&1 && break
  sleep 2
done

if [ ! -d "$SRC/.git" ]; then
  git clone "$REPO_URL" "$SRC"
fi
cd "$SRC"

# Rebuild only when the checked-out/built ref differs from the pinned one.
if [ "$(cat "$STAMP" 2>/dev/null || true)" = "$ref" ] && [ "$(git rev-parse HEAD)" = "$ref" ]; then
  echo "ccflare already built at $ref; nothing to do."
  exit 0
fi

git fetch origin
git checkout -q "$ref"

# bun install (no --frozen-lockfile: reproducibility comes from the pinned commit,
# and we don't want a lockfile-format drift between bun versions to hard-fail).
# Dependency postinstalls are off by default in bun, so the unused desktop app's
# electrobun runtime is never downloaded; we only build the server's dashboard.
bun install
bun run build:clients

echo "$ref" > "$STAMP"
echo "ccflare built at $ref."
