# Activepieces

Self-hosted Activepieces (MIT-licensed n8n alternative), synced by Argo.
Postgres is the external `postgres` LXC, same as pulse. Redis is shared with
pulse's in-cluster instance (`cluster/apps/pulse/redis.yaml`, now PVC-backed)
rather than a separate one — Activepieces uses `AP_REDIS_DB=1` to keep its keys
out of pulse's keyspace (DB 0).

## Pieces

- `namespace.yaml` - the `activepieces` namespace
- `app.yaml` - the single image serving frontend + API/execution engine on :80
- `httproute.yaml` - `ap.mert574.dev` and `ap.k3s.internal` -> the activepieces service
- `create-secrets.sh` - builds `activepieces-secrets`, bootstraps the admin
  account, mirrors its password into Vaultwarden, and configures the bifrost
  AI provider, all headless, safe to re-run

## Image

`ghcr.io/activepieces/activepieces:latest` — public, no pull secret needed
(unlike pulse's private GHCR images).

## First deploy (once)

1. `ACTIVEPIECES_DB_PASSWORD` in the sops env (`secrets/homelab.enc.env`) and the
   same value as `AP_POSTGRES_PASSWORD` in `secrets/activepieces.env.enc` — the
   `postgres` NixOS host reads the former to set the role's password
   (`nix/hosts/postgres.nix`), the app reads the latter to connect.
2. Rebuild `postgres` (new `activepieces` db/role) and `cloudflared` (new
   `ap.mert574.dev` route).
3. With KUBECONFIG + `SOPS_AGE_KEY_FILE` set: `./create-secrets.sh`. This also
   runs automatically via `cluster/bootstrap/up.sh` on a fresh k3s VM.
4. Argo syncs `app.yaml` + `httproute.yaml`.
5. Add the `ap.mert574.dev` Cloudflare DNS route and the `ap.k3s.internal`
   entry in `nix/lan-hosts`.

## AI provider (bifrost)

Fully automated in `create-secrets.sh`. Bifrost's OpenAI-SDK-compat route
fans out across its registered accounts: `http://bifrost.internal/openai`
(LibreChat/Activepieces append `/chat/completions`), with model ids prefixed
(`anthropic/claude-sonnet-5`, not bare `claude-sonnet-5`). No real API key
needed, Bifrost ignores whatever's sent. See `nix/hosts/bifrost.nix` for the
fuller writeup of this API shape.

## TODO before it serves traffic

- Pin the image tag (currently `:latest`, a moving tag) instead of tracking
  upstream automatically.
