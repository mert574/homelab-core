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

- [ ] Build the unattended Proxmox USB (`bootstrap/build-iso.sh`) - see `bootstrap/`
- [ ] Host pinned to `192.168.178.100/24`, filesystem **LVM-thin**
- [ ] No API token step: tofu logs in as `root@pam` with the baked install password
      (`providers.tf`), so this is hands-off
- [ ] Templates are fetched by `bootstrap.sh` (`ensure_templates`): Debian LXC via
      `pveam`, NixOS LXC built with nixos-generators. Debian cloud image is pulled by tofu
- [ ] `bootstrap/host-network/install.sh` runs from the bootstrap (vmbr1 for the ai box)
- [ ] `bootstrap/host-network/wifi-setup.sh` with `WIFI_IFACE` set - only if you want the
      Wi-Fi fallback uplink (not run by the bootstrap)
- [ ] (optional) host swap + `vm.swappiness=10` buffer

## 2. Secrets

- [ ] `cp secrets/homelab.env.example secrets/homelab.env`, fill every `REPLACE`
- [ ] `sops --encrypt secrets/homelab.env > secrets/homelab.enc.env`; delete the plaintext
- [ ] The bootstrap installs the master age key on every host (one key, no per-host
      recipients) at `/var/lib/sops-nix/key.txt`
- [ ] JWT PEM is multiline: keep it quoted in the env, or mount it as a file and set
      `PULSE_JWT_PRIVATE_KEY_PATH`
- [ ] `VAULTWARDEN_ADMIN_TOKEN` in the env gates the Vaultwarden `/admin` panel
      (`openssl rand -base64 48`, or an argon2 hash from `vaultwarden hash`)

## 3. Guests (Layer 2, tofu)

- [ ] Runs from `bootstrap.sh` (tofu init/apply). No `terraform.tfvars`: the creds come
      from the sops env as `TF_VAR_*` (`pve_password`, `ct_root_password`, `ssh_public_key`)
- [ ] SSH key is already set in `nix/modules/base.nix` (the homelab key)
- [ ] `apply-nixos.sh` skips `cloudflared` + `media` by default (they need Layer-3 creds);
      run with `HOMELAB_ALL_HOSTS=1` once those secret files exist

## 4. NixOS hosts

- [ ] LAN names come from one file, `network/lan-hosts`. NixOS guests include it via
      `networking.extraHosts`; `scripts/inject-hosts.sh` (run by the bootstrap) spreads
      it to the Proxmox host, the Debian LXCs and the k3s VM. Re-run it after editing
      the file. The k3s VM step needs its guest agent up, else it skips with a note.
- [ ] `scripts/apply-nixos.sh` configures every NixOS guest (nixos-rebuild inside
      each via pct). The bootstrap runs it; run it by hand to re-apply after edits.
- [ ] First-boot check: if a box has no IP, set `proxmoxLXC.manageNetwork` (see `nix/README.md`)
- [ ] **garage** layout, the nix-cache bucket, its alias/website and the CI write
      key are set up automatically by the `garage-setup` service in
      `nix/hosts/garage.nix` (`scripts/garage-setup.sh`). The SPA bucket is still in
      `cluster/apps/pulse/README.md` (move it into `ensure_site` when you want it
      automated too).
- [ ] **Nix binary cache (Garage)**: lets re-applies pull host closures prebuilt
      instead of rebuilding on each box (first boot still builds locally, that's
      fine). The bucket/DNS/key are all in code; only the secret values are yours:
  - `nix-store --generate-binary-cache-key nix-cache nix-cache.secret nix-cache.public`,
    then put `nix-cache.public` in `nix/modules/base.nix` (`trusted-public-keys`)
    and `nix-cache.secret` in the GitHub secret `NIX_CACHE_SIGNING_KEY`
  - fill `NIX_CACHE_S3_ACCESS_KEY` / `NIX_CACHE_S3_SECRET_KEY` in the sops env AND
    as GitHub secrets (same values: garage imports them, CI pushes with them)
  - once the in-cluster runner exists, set repo variable `HOMELAB_RUNNER=true` to
    activate the `nix-cache-push` job
- [ ] **cloudflared**: `cloudflared tunnel create homelab` -> save the creds JSON as
      `secrets/cloudflared.creds.enc`; put the tunnel UUID, the Gateway LB IP, and your
      hostnames in `nix/hosts/cloudflared.nix`. Ingress is locally-managed there; the
      only per-hostname step in Cloudflare is a DNS route so the name resolves to the
      tunnel. One tunnel serves both zones. Add a route per hostname (must be inside a
      zone whose nameservers point at Cloudflare):
  - `pulsepager.com`, `app.pulsepager.com`
  - `mert574.dev`: `media`, `requests`, `garage`, `proxmox`, `ccflare`, `pw`
  - ```
    for h in media.mert574.dev requests.mert574.dev garage.mert574.dev \
             proxmox.mert574.dev ccflare.mert574.dev pw.mert574.dev; do
      cloudflared tunnel route dns homelab "$h"
    done
    ```
    (creates a proxied CNAME -> `<tunnel-uuid>.cfargotunnel.com`; the dashboard works too)
  - Keep *arr/qBittorrent/etc. LAN-only. `media`/`requests` (Jellyfin/Jellyseerr),
    `garage` (S3 API) and `pw` (Vaultwarden) are public with app-level auth;
    **`proxmox` and `ccflare` must sit behind Cloudflare Access** (Zero Trust ->
    Access -> Applications: one self-hosted app per hostname, e.g. an allow policy on
    your email). Access is dashboard/API-only here (no cloudflare TF provider), so
    it's a manual step — do it before the DNS route goes live to avoid exposing them
    unauthenticated.
  - **Do NOT put `pw` (Vaultwarden) behind Cloudflare Access** — the Access login
    interstitial breaks the Bitwarden mobile/browser API clients. It relies on its
    own auth instead; lock down `/admin` separately (see §9).
  - Note: routing S3 (`garage`) through Cloudflare's proxy caps request body size on
    the free plan (~100 MB) and rewrites headers; fine for small assets, not big
    multipart uploads. Use the LAN endpoint for those.

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

## 9. Vaultwarden (password vault)

- [ ] Set `VAULTWARDEN_ADMIN_TOKEN` in the sops env (§2) and add the `pw.mert574.dev`
      tunnel route (§4). The service (`nix/hosts/vaultwarden.nix`) comes up with
      `apply-nixos.sh vaultwarden`; state lives at `/var/lib/bitwarden_rs` in CT 112.
- [ ] First account (signups are closed): open `https://pw.mert574.dev/admin`, log in
      with the admin token, **Invite User** for your own email. The invited email can
      then register at `https://pw.mert574.dev` even with `SIGNUPS_ALLOWED=false`.
      (No SMTP configured, so there's no invite email — just register that email
      directly after inviting it.) Enable 2FA on the account once you're in.
- [ ] Lock down `/admin` after setup: leave the token set but treat that URL as
      sensitive, or set `config.DISABLE_ADMIN_TOKEN = true` to turn the panel off
      entirely once you no longer need it (re-enable to invite more users).
- [ ] **Back up** `/var/lib/bitwarden_rs` — it *is* the vault. At minimum the
      `db.sqlite3` + `rsa_key*` + `attachments/`.
- [ ] Optional: register a family member the same way (invite from `/admin`).

## Not yet verified (treat first boot as testing, not guaranteed)

- Nix configs pass `nix flake check` (eval) and CI builds every host toplevel, but
  they've never run on a real box; expect small runtime fixes, esp. the postgres
  password unit, the cloudflared sops template, and the garage `_file` options.
- The Garage Nix cache is unverified until the machine is up. The `garage-setup`
  service's exact CLI calls (`layout assign/apply`, `bucket alias`, `key import`)
  may need tweaks against the pinned garage version, and the read path assumes
  Garage's web port matches `Host: nix-cache.garage.internal:3902` to the bucket alias
  with the port stripped (if it doesn't, alias the bucket `nix-cache.garage.internal:3902`
  or move the web serving to port 80).
- k8s manifests are not cluster-tested: Cilium values, the OCI-Helm Argo sources (ARC),
  the Gateway -> external-Garage routing, and ARC chart `0.14.2` may need tweaks.
- Pulse images have never been built; the first `docker build` may surface a fix.
- bpg provider attribute names can drift between versions; `tofu plan` will tell you.
- Verify Pulse's real health paths (`/healthz`, `/readyz`) and OAuth callback paths
  against the code; I assumed them.
- Pin image tags (currently `:main`, a moving tag) or add Argo Image Updater.
- Media stack is unverified: the `vpn-confinement` option names, the qbittorrent/
  minidlna module, and podman-in-LXC for the containerised apps.

_Vaultwarden (CT 112) has been deployed and verified end-to-end — service +
secret plumbing, `/alive` on LAN and public, and the web vault at
`pw.mert574.dev`. Note: a stale `NXDOMAIN` for a new tunnel hostname can linger
in Pi-hole/client caches; flush with `pihole restartdns` (or restart
`pihole-FTL`) and the client resolver if a fresh public name won't resolve._
