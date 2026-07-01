#!/usr/bin/env bash
# Baked into the auto-install ISO and run once on the first boot of the fresh
# Proxmox host, after the network is up (ordering = "network-online" in
# answer.toml). It reads the age private key off the USB, clones this repo, and
# hands off to bootstrap.sh unattended. No SSH, no paste.
#
# The age key is NOT on the ISO. It's on a small filesystem labeled HOMELAB (a
# second USB stick, or a partition you add after flashing) holding a file
# `age.key`. This script mounts it read-only, copies the key to tmpfs, releases
# the stick, and shreds the key once bootstrap has consumed it.
#
# Runs as root. Max size is 1 MiB.

set -euo pipefail

MARKER="/var/lib/homelab-first-boot.done"
LOG="/var/log/homelab-first-boot.log"
KEY_LABEL="HOMELAB"
KEY_NAME="age.key"
REPO_URL="https://github.com/mert574/homelab-core"
REPO_DIR="/root/homelab-core"

[ -f "$MARKER" ] && exit 0
exec > >(tee -a "$LOG") 2>&1
echo "== homelab first-boot $(date -u +%FT%TZ) =="

# A recovery helper + banner for the manual path, in case the auto run fails.
cat > /usr/local/sbin/homelab-bootstrap <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /root
[ -d "$REPO_DIR" ] || git clone "$REPO_URL"
cd "$REPO_DIR"
echo "Repo ready. Run: ./bootstrap/bootstrap.sh   (paste age key, then Ctrl-D)"
EOF
chmod +x /usr/local/sbin/homelab-bootstrap
cat > /etc/motd <<'EOF'

  homelab-core host. If the unattended bootstrap didn't finish, check
  /var/log/homelab-first-boot.log and /var/log/homelab-bootstrap.log, then run
  homelab-bootstrap and ./bootstrap/bootstrap.sh by hand (see DEPLOY.md).

EOF

# 1. Find the age key on the HOMELAB volume.
keydev="$(blkid -L "$KEY_LABEL" 2>/dev/null || true)"
if [ -z "$keydev" ]; then
  echo "no volume labeled $KEY_LABEL found; cannot bootstrap unattended." >&2
  echo "plug in the key stick and run homelab-bootstrap by hand." >&2
  exit 1
fi
install -d -m 700 /mnt/homelab-key
mount -o ro "$keydev" /mnt/homelab-key
if [ ! -f "/mnt/homelab-key/$KEY_NAME" ]; then
  echo "$KEY_LABEL volume has no $KEY_NAME." >&2
  umount /mnt/homelab-key || true
  exit 1
fi
# 2. Copy the key to tmpfs (never a persistent disk), release the stick.
install -d -m 700 /run/homelab
install -m 600 "/mnt/homelab-key/$KEY_NAME" /run/homelab/age.key
umount /mnt/homelab-key && rmdir /mnt/homelab-key

# 3. Minimal tool to clone; bootstrap.sh installs the rest.
export DEBIAN_FRONTEND=noninteractive
command -v git >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq git; }
[ -d "$REPO_DIR" ] || git clone "$REPO_URL" "$REPO_DIR"

# 4. Run bootstrap detached, so a long tofu/nixos-rebuild run isn't bound to the
#    first-boot service timeout. Key is piped on stdin, then shredded.
touch "$MARKER"
systemd-run --unit=homelab-bootstrap --collect --property=Type=oneshot \
  bash -c "'$REPO_DIR/bootstrap/bootstrap.sh' < /run/homelab/age.key 2>&1 | tee -a /var/log/homelab-bootstrap.log; shred -u /run/homelab/age.key"
echo "bootstrap launched as systemd unit homelab-bootstrap; see /var/log/homelab-bootstrap.log"
