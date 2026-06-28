# Deploy runbook

The single, ordered checklist to stand this up. Per-directory READMEs have the
detail; this is the sequence and the manual bits. Nothing here is auto-run yet.

## 0. Off-box prerequisites

- [ ] GitHub **PAT** (repo scope) for ARC and GHCR pulls -> `GITHUB_RUNNER_TOKEN`, `GIT_HTTP_TOKEN`
- [ ] Cloudflare **tunnel** created (`cloudflared tunnel create`) -> creds JSON saved as `secrets/cloudflared.creds.enc`
- [ ] Google + GitHub **OAuth apps** created (client id/secret, redirect URLs)
- [ ] **age key**: `age-keygen -o age.key`; put the public key in `.sops.yaml` (`master`)
- [ ] Confirm the **domain** + DNS is on Cloudflare (`pulsepager.com`)
- [ ] Confirm the M720q actually has a **Wi-Fi card** (for the fallback uplink)

## 1. Host install (Layer 0-1)

- [ ] Build the unattended Proxmox USB (answer.toml + first-boot) - see `bootstrap/`
- [ ] Host pinned to `192.168.178.100/24`, filesystem **LVM-thin**
- [ ] Create the Proxmox **API token** -> `pve_api_token`
- [ ] Download templates on the node: NixOS LXC (`var.nixos_ct_template`), Debian LXC
      (`pveam ... debian-13-standard`), and the Debian cloud image is pulled by tofu
- [ ] `bootstrap/host-network/install.sh` (vmbr1 isolation bridge for the ai box)
- [ ] `bootstrap/host-network/wifi-setup.sh` with `WIFI_IFACE` set to the real device
- [ ] (optional) host swap + `vm.swappiness=10` buffer

## 2. Secrets

- [ ] `cp secrets/homelab.env.example secrets/homelab.env`, fill every `REPLACE`
- [ ] `sops --encrypt secrets/homelab.env > secrets/homelab.enc.env`; delete the plaintext
- [ ] The bootstrap installs the master age key on every host (one key, no per-host
      recipients) at `/var/lib/sops-nix/key.txt`
- [ ] JWT PEM is multiline: keep it quoted in the env, or mount it as a file and set
      `PULSE_JWT_PRIVATE_KEY_PATH`

## 3. Guests (Layer 2, tofu)

- [ ] Set the real **SSH public key** in `nix/modules/base.nix` and `terraform.tfvars`
- [ ] `cp tofu/terraform.tfvars.example tofu/terraform.tfvars`, fill token/password/key
- [ ] `tofu -chdir=tofu init && tofu -chdir=tofu apply`

## 4. NixOS hosts

- [ ] `nixos-rebuild switch --flake .#<host>` for postgres, cloudflared, garage,
      admin, ai, playground (admin/ai/playground are on-demand)
- [ ] First-boot check: if a box has no IP, set `proxmoxLXC.manageNetwork` (see `nix/README.md`)
- [ ] **garage** runtime: `garage layout assign ...`, then create the SPA bucket
      (`bucket create/alias/website/key`) - see `cluster/apps/pulse/README.md`
- [ ] **cloudflared**: `cloudflared tunnel create homelab` -> save the creds JSON as
      `secrets/cloudflared.creds.enc`; put the tunnel UUID, the Gateway LB IP, and your
      media hostnames in `nix/hosts/cloudflared.nix`; add a DNS route per hostname
      (`cloudflared tunnel route dns ...` or the dashboard). Expose only Jellyfin +
      Jellyseerr; keep *arr/qBittorrent/etc. LAN-only (or behind Cloudflare Access)

## 5. Cluster (Layer 3)

- [ ] Set the repo URL in `cluster/bootstrap/root-app.yaml`
- [ ] `cluster/bootstrap/install.sh` (Gateway CRDs -> Cilium -> Argo -> root app)
- [ ] ARC secret: `kubectl -n arc-runners create secret generic arc-github
      --from-literal=github_token=$GITHUB_RUNNER_TOKEN` (see `cluster/apps/arc/README.md`)
- [ ] Verify: L2 policy interface regex `^e.+` matches the k3s VM NIC; if cilium pods
      crashloop, check the k3s cgroup note

## 6. Pulse

- [ ] CI builds + pushes images to GHCR (the pulse repo's `.github/workflows/images.yml`)
- [ ] Set the real domain in `cluster/apps/pulse/config.yaml` (`PULSE_APP_BASE_URL`,
      redirect URLs) and `httproute.yaml` hostname + the Garage bucket alias
- [ ] `cluster/apps/pulse/create-secrets.sh` (namespace + pull secret + pulse-secrets)
- [ ] Bootstrap the DB schema **once** from the `pulse-schema` image
- [ ] Add the asset-push `web` job (`runs-on: homelab` -> build -> `aws s3 sync` to Garage);
      needs a Garage access key as repo secrets
- [ ] Add `app.pulsepager.com` to the Cloudflare tunnel -> Gateway LB IP

## 7. Router (Fritz!Box)

- [ ] Reserve `.100` for the host in DHCP
- [ ] Point the Fritz!Box DNS at the Pi-hole IP (`.101`)

## 8. Media box

- [ ] Get a Mullvad WireGuard config, save it encrypted:
      `sops -e --input-type binary mullvad.conf > secrets/mullvad.wg.enc`
- [ ] WireGuard in an unprivileged LXC may need `/dev/net/tun` passed in (device +
      cgroup allow on the container) or running it privileged. If the VPN namespace
      won't start, check that first.
- [ ] DLNA is `services.minidlna` (declarative), so the TV finds "Home Media" on the
      LAN with no manual step
- [ ] **digarr**: fill `secrets/digarr.env.enc` from digarr's `.env.example`
      (DATABASE_URL -> the postgres LXC, AI provider key, initial creds, LIDARR_API_KEY);
      set the same `DIGARR_DB_PASSWORD` in the homelab env
- [ ] Register **Byparr** in Prowlarr as a FlareSolverr proxy (`http://localhost:8191`)
      and tag the indexers that need it
- [ ] **SuggestArr** web UI: set the TMDb key + Jellyfin and Jellyseerr URLs/keys
      (auto-discovery -> Jellyseerr -> Sonarr/Radarr)
- [ ] **QuickSync**: host must expose `/dev/dri` (i915 driver, default on Proxmox).
      Then enable Intel QSV/VAAPI in Jellyfin Playback settings. Unprivileged LXC
      may need the render device gid mapped so jellyfin can read
      `/dev/dri/renderD128` (set `gid` on the device_passthrough, or check `vainfo`)
- [ ] Library at `/srv/media`, downloads at `/srv/downloads`; Mullvad has no port
      forwarding (fewer peers, still works)
- [ ] Storage: the 64GB disk will fill, plan a second/larger disk for the library

## Not yet verified (treat first boot as testing, not guaranteed)

- Nix configs are not `nix flake check`'d (no nix here); expect small fixes, esp. the
  postgres password unit, the cloudflared sops template, and the garage `_file` options.
- k8s manifests are not cluster-tested: Cilium values, the OCI-Helm Argo sources (ARC),
  the Gateway -> external-Garage routing, and ARC chart `0.14.2` may need tweaks.
- Pulse images have never been built; the first `docker build` may surface a fix.
- bpg provider attribute names can drift between versions; `tofu plan` will tell you.
- Verify Pulse's real health paths (`/healthz`, `/readyz`) and OAuth callback paths
  against the code; I assumed them.
- Pin image tags (currently `:main`, a moving tag) or add Argo Image Updater.
- Media stack is unverified: the `vpn-confinement` option names, the qbittorrent/
  lidarr/minidlna modules, podman-in-LXC for digarr, and digarr's exact env (taken
  from a repo summary, not its `.env.example`).
