#!/usr/bin/env bash
# No-touch Layer 3, run on the Proxmox host after Layer 2. Waits for the k3s VM,
# grabs its kubeconfig, installs kubectl+helm, bootstraps the cluster
# (Gateway/Cilium/Argo/root-app), creates each app's secrets (Pulse,
# Activepieces), and (if a token is set) the ARC runner secret. The caller
# sources the sops env first, so GIT_HTTP_TOKEN / GITHUB_RUNNER_TOKEN /
# SOPS_AGE_KEY_FILE are already exported. Also invoked automatically by tofu
# (see the k3s_bootstrap null_resource in tofu/k3s.tf) on every apply, so this
# whole script must stay idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
[ -n "${GIT_HTTP_TOKEN:-}" ] || . "$REPO_ROOT/scripts/load-env.sh"
K3S_VMID=104
K3S_IP="$(awk '$0 !~ /^#/ { for (i=2;i<=NF;i++) if ($i == "k3s.internal") print $1 }' "$REPO_ROOT/nix/lan-hosts")"
: "${K3S_IP:?k3s.internal not found in nix/lan-hosts}"
export KUBECONFIG=/root/.kube/config

# 1. tools on the host
if ! command -v kubectl >/dev/null 2>&1; then
  kver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL "https://dl.k8s.io/release/${kver}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
fi
command -v helm >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 2. wait for k3s on the VM, then fetch + rewrite the kubeconfig
echo "waiting for k3s on VM $K3S_VMID (its cloud-init installs it)..."
install -d -m 700 /root/.kube
for _ in $(seq 1 60); do
  raw="$(qm guest exec "$K3S_VMID" -- cat /etc/rancher/k3s/k3s.yaml 2>/dev/null \
    | python3 -c 'import json,sys
out = json.load(sys.stdin).get("out-data", "")
print(out, end="") if "clusters:" in out else sys.exit(1)' 2>/dev/null)" && break
  sleep 5
done
printf '%s' "$raw" | sed "s#https://127.0.0.1:6443#https://${K3S_IP}:6443#" > "$KUBECONFIG"
chmod 600 "$KUBECONFIG"
kubectl get nodes

# 3. cluster: Gateway CRDs -> Cilium -> Argo -> root app
bash "$REPO_ROOT/cluster/bootstrap/install.sh"

# 4. Pulse secrets (namespace, GHCR pull, pulse-secrets, pulse-jwt)
bash "$REPO_ROOT/cluster/apps/pulse/create-secrets.sh"

# 4b. Activepieces secrets + headless admin bootstrap + Vaultwarden mirror
bash "$REPO_ROOT/cluster/apps/activepieces/create-secrets.sh"

# 5. ARC self-hosted runners (optional; needs a token with the right scope)
if [ -n "${GITHUB_RUNNER_TOKEN:-}" ]; then
  kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n arc-runners create secret generic arc-github \
    --from-literal=github_token="$GITHUB_RUNNER_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Layer 3 up. Argo CD is syncing cluster/apps; Pulse and Activepieces will roll out once their images pull."
