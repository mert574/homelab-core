#!/usr/bin/env bash
# Fully unattended reconcile loop, run by the homelab-auto-apply systemd timer
# on the Proxmox host (see bootstrap/systemd/). Pulls the repo, then applies
# tofu -- which in turn triggers null_resource.k3s_bootstrap /
# null_resource.lan_hosts_sync whenever their inputs actually changed. No
# human needs to type anything for infra to reconcile itself; this is the
# thing that runs instead.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

git pull --ff-only

# shellcheck source=/dev/null
. scripts/load-env.sh

tofu -chdir=tofu apply -auto-approve
