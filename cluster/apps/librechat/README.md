# LibreChat

A self-hosted chat UI (`ghcr.io/danny-avila/librechat`) plus its own MongoDB, both
in-cluster, synced by Argo. Wired to Bifrost (the Anthropic proxy on the LXC at
`192.168.178.113`) as a custom OpenAI-compatible endpoint, with three Claude
model presets always selected (no empty "nothing chosen" state).

This app was originally deployed by hand, straight into the cluster, and was
never in git. Brought under GitOps here after the Cloudflare tunnel route for
`ai.mert574.dev` turned out to have been missing the whole time (fixed in
`nix/hosts/cloudflared.nix`), which was the moment we noticed it wasn't backed
by anything durable, one k3s VM rebuild away from losing the chat history for
real.

## Pieces

- `app.yaml` - the `librechat` Deployment/Service and the `mongodb`
  Deployment/Service. Mongo uses `strategy: Recreate` since only one pod can
  mount the ReadWriteOnce PVC at a time.
- `pvc.yaml` - `mongodb-data`, 5Gi, `local-path`. Matches the pre-existing bound
  volume exactly so the first Argo sync adopts it instead of provisioning a new
  (empty) one.
- `configmap.yaml` - `librechat-config` (env vars: registration/social login
  off, email login on, points at the in-cluster Mongo) and `librechat-file`
  (the mounted `librechat.yaml`: the Bifrost custom endpoint + model presets).
- `httproute.yaml` - `ai.mert574.dev` + `librechat.k3s.internal` through the
  Cilium Gateway, same pattern as Activepieces and Pulse.
- `create-secrets.sh` - builds `librechat-secrets` (JWT/CREDS keys) from the
  env, resets the real login's password to a freshly generated one (never the
  password that was live before this), and mirrors it into Vaultwarden.

## First deploy (once, adopting the existing live app)

1. `./create-secrets.sh` with `KUBECONFIG` set and the sops env available.
2. Commit + push; Argo's `root` app picks up this directory automatically
   (`prune: true, selfHeal: true` on `cluster/apps`, recursive).
3. Watch `kubectl get pods -n librechat` during the first sync - expect no
   crash loops and the existing chat history to still be there once
   `librechat` is `Running` again (proves the PVC was adopted, not recreated).
4. The Cloudflare tunnel route for `ai.mert574.dev` needs
   `nixos-rebuild switch` on the cloudflared LXC to pick up the
   `nix/hosts/cloudflared.nix` change - that's a manual step, not automatic.
