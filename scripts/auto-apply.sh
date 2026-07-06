#!/usr/bin/env bash
# Unattended reconcile loop, run by the homelab-auto-apply systemd timer on
# the Proxmox host (see bootstrap/systemd/). Pulls the repo, plans, and only
# auto-applies if the plan contains no delete/replace actions. A plan with any
# destroy or replace is logged (journalctl -u homelab-auto-apply) and left for
# a human to review with `tofu plan` themselves -- never auto-approved.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

git pull --ff-only

# shellcheck source=/dev/null
. scripts/load-env.sh

cd tofu
plan_file="$(mktemp)"
trap 'rm -f "$plan_file"' EXIT

tofu plan -out="$plan_file"

destructive="$(tofu show -json "$plan_file" | python3 -c '
import json, sys
plan = json.load(sys.stdin)
bad = [
    rc["address"]
    for rc in plan.get("resource_changes", [])
    if "delete" in rc["change"]["actions"]
]
print("\n".join(bad))
')"

if [ -n "$destructive" ]; then
  echo "auto-apply: plan wants to delete/replace the following, refusing to auto-approve:"
  echo "$destructive"
  echo "review with: cd tofu && tofu plan"
  exit 1
fi

tofu apply "$plan_file"
