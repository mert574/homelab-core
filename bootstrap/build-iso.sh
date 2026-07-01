#!/usr/bin/env bash
# Bake the unattended-install ISO from the official Proxmox ISO + answer.toml +
# first-boot.sh.
#
# Usage:
#   ./bootstrap/build-iso.sh /path/to/proxmox-ve_9.2-1.iso [output.iso]
#
# It prompts for the root password (hidden), hashes it with SHA-512, fills a
# throwaway copy of answer.toml with the hash, and bakes. No plaintext password
# and no filled-in answer.toml is ever written into the repo.
#
# proxmox-auto-install-assistant is Linux + amd64 only. On a Linux host that has
# it installed, this runs it directly. Otherwise it runs it in a Debian amd64
# container (needs docker; on Apple Silicon that is emulated, which is slow but
# works). Notes learned the hard way, encoded below:
#   - colima only mounts your home dir, so the work dir must live under $HOME.
#   - the amd64 emulation rejects the ISO ("not able to be installed
#     automatically") if prepare-iso writes its output onto the virtiofs mount;
#     write to container-local disk, then copy the result back.
#   - the trixie repo key isn't on the download mirror; fetch it from enterprise.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ISO="${1:?usage: build-iso.sh <source.iso> [output.iso]}"
OUT_ISO="${2:-${SRC_ISO%.iso}-auto.iso}"
TRIXIE_KEY_URL="https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg"

for f in answer.toml first-boot.sh; do
  [ -f "$HERE/$f" ] || { echo "missing $f next to this script" >&2; exit 1; }
done
[ -f "$SRC_ISO" ] || { echo "no such ISO: $SRC_ISO" >&2; exit 1; }

native_assistant() { command -v proxmox-auto-install-assistant >/dev/null 2>&1; }

# --- root password -> SHA-512 crypt hash (never stored in the repo) -----------
read -rsp "Root password for the Proxmox host: " PW1; echo
read -rsp "Repeat: " PW2; echo
[ "$PW1" = "$PW2" ] || { echo "passwords differ" >&2; exit 1; }
[ -n "$PW1" ] || { echo "empty password" >&2; exit 1; }

if openssl passwd -6 -stdin </dev/null >/dev/null 2>&1; then
  HASH="$(printf '%s' "$PW1" | openssl passwd -6 -stdin)"   # Linux / real openssl
else
  # macOS LibreSSL has no -6; hash in a small container (native arch is fine).
  HASH="$(printf '%s' "$PW1" | docker run --rm -i debian:trixie-slim openssl passwd -6 -stdin)"
fi
unset PW1 PW2
[ -n "$HASH" ] || { echo "hashing failed" >&2; exit 1; }

# --- assemble a work dir (under $HOME so colima can mount it) ------------------
WORK="$HOME/.cache/homelab-iso-build/work.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
sed "s|__ROOT_PASSWORD_HASHED__|$(printf '%s' "$HASH" | sed 's/[&|]/\\&/g')|" \
  "$HERE/answer.toml" > "$WORK/answer.toml"
cp "$HERE/first-boot.sh" "$WORK/first-boot.sh"
cp "$SRC_ISO" "$WORK/src.iso"

# --- bake ---------------------------------------------------------------------
if native_assistant; then
  ( cd "$WORK"
    proxmox-auto-install-assistant validate-answer answer.toml
    proxmox-auto-install-assistant prepare-iso src.iso --fetch-from iso \
      --answer-file answer.toml --on-first-boot first-boot.sh --output out.iso )
else
  command -v docker >/dev/null 2>&1 || { echo "need docker (or the assistant) to bake" >&2; exit 1; }
  echo "baking in a Debian amd64 container..." >&2
  curl -fsSL "$TRIXIE_KEY_URL" -o "$WORK/proxmox-release-trixie.gpg"
  docker run --rm --platform linux/amd64 -v "$WORK":/work -w /root debian:trixie-slim \
    bash -euo pipefail -c '
      export DEBIAN_FRONTEND=noninteractive
      cp /work/proxmox-release-trixie.gpg /etc/apt/trusted.gpg.d/
      echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
        > /etc/apt/sources.list.d/pve.list
      apt-get update -qq >/dev/null
      apt-get install -y -qq --no-install-recommends proxmox-auto-install-assistant >/dev/null
      proxmox-auto-install-assistant validate-answer /work/answer.toml
      # input from the mount, output to container-local disk, then copy back.
      proxmox-auto-install-assistant prepare-iso /work/src.iso --fetch-from iso \
        --answer-file /work/answer.toml --on-first-boot /work/first-boot.sh \
        --output /root/out.iso
      cp /root/out.iso /work/out.iso
    '
fi

mv "$WORK/out.iso" "$OUT_ISO"
echo
echo "baked: $OUT_ISO"
shasum -a 256 "$OUT_ISO" 2>/dev/null || sha256sum "$OUT_ISO"
echo "Flash it to USB (see bootstrap/README.md)."
