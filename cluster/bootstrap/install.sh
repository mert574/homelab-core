#!/usr/bin/env bash
# Bootstrap the cluster, in order: Gateway API CRDs -> Cilium -> Argo CD -> the
# root app-of-apps. Run once against the fresh k3s node with KUBECONFIG set.
# After this, Argo CD syncs everything under cluster/apps from git.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Gateway API CRDs (Cilium needs them present before gatewayAPI is enabled)
gw_ver="$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/gateway-api/releases/latest \
  | grep -oE '"tag_name": *"[^"]+"' | grep -oE 'v[0-9.]+')"
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${gw_ver}/standard-install.yaml"

# 2. Cilium: CNI + kube-proxy replacement + LB IPAM + Gateway API + Hubble.
# The cluster sits NotReady until this lands.
helm repo add cilium https://helm.cilium.io >/dev/null
helm repo update >/dev/null
helm upgrade --install cilium cilium/cilium -n kube-system -f "$HERE/cilium-values.yaml"
kubectl -n kube-system rollout status ds/cilium --timeout=300s

# 3. Argo CD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm upgrade --install argocd argo/argo-cd -n argocd -f "$HERE/argocd-values.yaml"
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

# 4. Root app-of-apps: Argo manages everything in cluster/apps from here on.
kubectl apply -f "$HERE/root-app.yaml"

echo "cluster bootstrapped. Argo CD is syncing cluster/apps."
