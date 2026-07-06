# Pulse

Pulse running in-cluster, synced by Argo. Simplified for one node:
single replicas, `PULSE_BUS=redis` (one in-cluster Redis is kv + bus, no Kafka),
Postgres is the external `postgres` LXC. The SPA is served from a Garage bucket,
the API from the cluster, and the Gateway routes between them by path (same
origin, so auth cookies work). Deep SPA routes (e.g. `/login`) that aren't real
objects fall back to `index.html` with a 200 in the Caddy layer in front of
Garage's web port -- see `nix/hosts/garage.nix`, not these manifests.

## Pieces

- `redis.yaml` - kv + event bus (no persistence)
- `api.yaml`, `billing.yaml` - the HTTP services
- `workers.yaml` - scheduler, worker, alerting, notifier (headless)
- `garage-web.yaml` - selector-less Service + EndpointSlice to the Garage LXC web port
- `httproute.yaml` - /api+/auth -> api service, everything else -> Garage bucket
  (the SPA; its deep-route 200 fallback is handled Garage-side, see intro)
- `migrate-job.yaml` - PreSync hook, applies migrations each sync
- `config.yaml` - non-secret env
- `create-secrets.sh` - builds `pulse-secrets` + the GHCR pull secret from the env

## Images

Go services + migrate/schema images come from the Pulse repo's
`.github/workflows/images.yml` (`ghcr.io/mert574/pulse-*:main`). The SPA is no
longer an image; its built assets go into the Garage bucket (below).

## The SPA bucket

The bucket (`pulse-app`), its `app.pulsepager.com` alias and website mode are
created automatically by the `garage-setup` service (`scripts/garage-setup.sh`,
`ensure_site pulse-app app.pulsepager.com`). The 404 -> `index.html` (200)
fallback for client-side routes is done in the Caddy layer in front of Garage's
web port (`nix/hosts/garage.nix`), so nothing about the bucket's website config
depends on it. Adding another SPA is one line in each of those two files.

The only manual bit is the CI write key used to push assets (creating it inside
the garage LXC, one-time):

```sh
garage key create pulse-web
garage bucket allow --read --write pulse-app --key pulse-web
```

Then push `web/dist` to `s3://pulse-app/`. See "Asset push" below for where that
runs.

## First deploy (once)

1. CI has pushed the service images to GHCR.
2. With KUBECONFIG set and the env sourced: `./create-secrets.sh`.
3. Bootstrap the empty DB schema once from `ghcr.io/mert574/pulse-schema:main`
   (one-off Job, same envFrom + the `ghcr` pull secret). Never run again.
4. Create the `pulse-web` write key (above) and push the assets; the bucket
   itself is already created by `garage-setup`.
5. Argo syncs the rest; the migrate hook runs before each sync afterwards.

## Asset push (open decision)

GitHub-hosted runners can't reach the home-LAN Garage, so `aws s3 sync` from the
existing CI won't work directly. Pick one: a self-hosted runner in the homelab
(the real CI/CD path), expose Garage's S3 port via a cloudflared tunnel so the
cloud CI can push with the access key, or sync from inside the homelab. Not wired
yet.

## TODO before it serves traffic

- Set your real domain in `config.yaml` (`PULSE_APP_BASE_URL`, redirect URLs),
  `httproute.yaml` (hostname), the bucket alias in `scripts/garage-setup.sh`
  (`ensure_site`) and, for the SPA host, `spaHosts` in `nix/hosts/garage.nix`;
  then add that hostname in the Cloudflare tunnel pointing at the Gateway LB IP.
- Fill the Pulse secrets in the env.
