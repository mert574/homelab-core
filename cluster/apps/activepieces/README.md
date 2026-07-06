# Activepieces

Self-hosted Activepieces (MIT-licensed n8n alternative), synced by Argo.
Postgres is the external `postgres` LXC, same as pulse. Redis is shared with
pulse's in-cluster instance (`cluster/apps/pulse/redis.yaml`, now PVC-backed)
rather than a separate one — Activepieces uses `AP_REDIS_DB=1` to keep its keys
out of pulse's keyspace (DB 0).

## Pieces

- `namespace.yaml` - the `activepieces` namespace
- `app.yaml` - the single image serving frontend + API/execution engine on :80
- `httproute.yaml` - `ap.mert574.dev` -> the activepieces service
- `create-secrets.sh` - builds `activepieces-secrets` from `secrets/activepieces.env.enc`

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
3. With KUBECONFIG + `SOPS_AGE_KEY_FILE` set: `./create-secrets.sh`.
4. Argo syncs `app.yaml` + `httproute.yaml`.
5. Add the `ap.mert574.dev` Cloudflare DNS route.

## AI provider (ccflare)

Activepieces doesn't have a reliable env var for a custom OpenAI-compatible
base URL — this moved to the admin UI in recent versions and a dedicated env
var for it has been flaky/regressed upstream. After first login, add an
OpenAI-compatible connection in Settings -> Connections pointing at
`http://ccflare.internal:8080` (ccflare is already an OpenAI/Anthropic-compatible
proxy, see `nix/hosts/ccflare.nix`), with whatever bearer key ccflare expects.

## TODO before it serves traffic

- Pin the image tag (currently `:latest`, a moving tag) instead of tracking
  upstream automatically.
