# Layer 3: GitOps (Cilium + Argo CD)

Run `bootstrap/install.sh` once against the fresh k3s node (KUBECONFIG set). It
installs, in order:

1. **Gateway API CRDs** (Cilium needs them before its Gateway API can turn on).
2. **Cilium** (`cilium-values.yaml`): CNI + kube-proxy replacement, LB IPAM + L2
   announcements (LAN IPs, replaces MetalLB), Gateway API (replaces Traefik),
   Hubble. The cluster is NotReady until this lands, that's expected.
3. **Argo CD**, then the **root app-of-apps** (`root-app.yaml`).

From there Argo syncs everything under `apps/` from git.

```
cluster/
  bootstrap/   # one-time install: cilium + argo + root app
  apps/
    networking/   # CiliumLoadBalancerIPPool, L2 policy, Gateway (synced by Argo)
    <your apps>   # add SaaS apps here (Deployment/Service + HTTPRoute to the Gateway)
```

## Traffic path

Cloudflare edge (public TLS) -> cloudflared LXC -> the Gateway's pinned LB IP
(`192.168.178.200`) -> Cilium routes by hostname (HTTPRoute) to the app ->
Postgres in its LXC over the LAN. Don't also terminate TLS at the Gateway.

## Notes

- Set the real repo URL in `root-app.yaml`.
- k3s + Cilium sometimes needs a cgroup tweak; if cilium pods crashloop on first
  boot, that's the first thing to check.
- Private app repos: give Argo CD repo credentials from `GIT_HTTP_TOKEN`.
