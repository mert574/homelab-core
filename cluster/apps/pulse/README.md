# Pulse

Pulse running in-cluster, synced by Argo. Simplified for one node:
single replicas, `PULSE_BUS=redis` (one in-cluster Redis is kv + bus, no Kafka),
Postgres is the external `postgres` LXC. The SPA is served from a Garage bucket,
the API from the cluster, and the Gateway routes between them by path (same
origin, so auth cookies work).

## Pieces

- `redis.yaml` - kv + event bus (no persistence)
- `api.yaml`, `billing.yaml` - the HTTP services
- `workers.yaml` - scheduler, worker, alerting, notifier (headless)
- `garage-web.yaml` - selector-less Service + EndpointSlice to the Garage LXC web port
- `httproute.yaml` - /api+/auth -> api service, everything else -> Garage bucket
- `migrate-job.yaml` - PreSync hook, applies migrations each sync
- `config.yaml` - non-secret env
- `create-secrets.sh` - builds `pulse-secrets` + the GHCR pull secret from the env

## Images

Go services + migrate/schema images come from the Pulse repo's
`.github/workflows/images.yml` (`ghcr.io/mert574/pulse-*:main`). The SPA is no
longer an image; its built assets go into the Garage bucket (below).

## The SPA bucket (one-time, on the garage LXC)

```sh
garage bucket create app.pulsepager.com
garage bucket alias  app.pulsepager.com app.pulsepager.com   # alias = the domain
garage bucket website --allow app.pulsepager.com
garage key create pulse-web
garage bucket allow --read --write app.pulsepager.com --key pulse-web
```

Then push `web/dist` to `s3://app.pulsepager.com/`. See "Asset push" below for
where that runs.

## First deploy (once)

1. CI has pushed the service images to GHCR.
2. With KUBECONFIG set and the env sourced: `./create-secrets.sh`.
3. Bootstrap the empty DB schema once from `ghcr.io/mert574/pulse-schema:main`
   (one-off Job, same envFrom + the `ghcr` pull secret). Never run again.
4. Create the SPA bucket and push the assets.
5. Argo syncs the rest; the migrate hook runs before each sync afterwards.

## Asset push (open decision)

GitHub-hosted runners can't reach the home-LAN Garage, so `aws s3 sync` from the
existing CI won't work directly. Pick one: a self-hosted runner in the homelab
(the real CI/CD path), expose Garage's S3 port via a cloudflared tunnel so the
cloud CI can push with the access key, or sync from inside the homelab. Not wired
yet.

## TODO before it serves traffic

- Set your real domain in `config.yaml` (`PULSE_APP_BASE_URL`, redirect URLs) and
  `httproute.yaml` (hostname) + the bucket alias, then add that hostname in the
  Cloudflare tunnel pointing at the Gateway LB IP.
- Fill the Pulse secrets in the env.
