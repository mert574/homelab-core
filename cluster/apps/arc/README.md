# ARC: on-demand GitHub Actions runners

Ephemeral runners in the cluster: scale 0 -> N when a job is queued, back to 0
when idle, so no always-on runner box. Runner pods reach Garage on the LAN like
any pod. A small always-on listener long-polls GitHub (no inbound webhook).

- `controller.yaml` - the ARC controller (arc-systems)
- `runner-set.yaml` - the scale set for the pulse repo (`runs-on: homelab`)
- `blog-runner-set.yaml` - the scale set for the blog repo (`runs-on: homelab-blog`)
- `homelab-core-runner-set.yaml` - the scale set for this repo (`runs-on: homelab-core`), used by the nix-cache-push job

A scale set binds to one repo and mert574 is a personal account, so each repo
that needs the homelab runners gets its own set. Both reuse the `arc-github` PAT
secret below, so that PAT must have access to every repo listed here.

## One-time secret (run with the env sourced)

ARC's listener authenticates with a PAT (repo scope), pre-created so it isn't in git:

```sh
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -
kubectl -n arc-runners create secret generic arc-github \
  --from-literal=github_token="$GITHUB_RUNNER_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Using it

In a workflow: `runs-on: homelab` (the runnerScaleSetName). The default runner
image is minimal, so a job that needs node + awscli either installs them
(`setup-node` + awscli) or runs in a container that has them. Cold start ~20-60s.
For the Pulse asset push: this is where the `web` job runs to `aws s3 sync
web/dist` to the Garage bucket.
