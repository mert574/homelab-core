# homelab-core

Infrastructure as code for my home server. One small box runs everything: DNS, a
shared Postgres instance for the apps, and a k3s cluster that runs them behind
Cloudflare tunnels.

The repo is public; the env is encrypted with SOPS + age.

## Hardware

- Lenovo ThinkCentre M720q (Tiny)
- Intel i5-9500T (6 cores, VT-x/VT-d)
- 16GB RAM
- 256GB SSD (single disk for now, no redundancy by choice)

## The shape of it

One physical box running Proxmox VE. On top of Proxmox:

- Stateful things live in their own LXC containers, kept out of the k3s cluster
  so rebuilding the cluster never touches their data.
- The k3s VM is stateless and disposable. Snapshot before experiments, roll back
  when something breaks.
- Cilium owns all cluster networking (CNI, load balancer IPs, ingress via Gateway
  API, network policy).
- cloudflared exposes the apps. It runs in its own LXC while the cluster is
  still something I rebuild often, so public traffic stays up across cluster
  rebuilds. Moves into the cluster later.

```
Internet
   |
Cloudflare edge (terminates public TLS)
   |  tunnel
cloudflared (LXC)
   |  HTTP to one stable LAN IP
Cilium Gateway (LoadBalancer IP from Cilium LB IPAM)
   |  host-based routing inside the cluster
app pods  ->  Postgres (LXC, over the LAN)
```

## Apps

The k3s VM runs the actual applications, each in `cluster/apps/<name>/` with its
own README:

- **Pulse** (`cluster/apps/pulse/`) - the original app this homelab was built
  around.
- **Activepieces** (`cluster/apps/activepieces/`) - self-hosted workflow
  automation, `ap.mert574.dev` / `ap.k3s.internal`. Bootstraps headlessly
  (admin account + AI provider setup) via `create-secrets.sh`, no manual UI
  step needed on a fresh deploy.

## Guest layout and RAM budget

16GB total. Always-on guests:

| Guest        | Type | vCPU | RAM    | Role                                 |
|--------------|------|------|--------|--------------------------------------|
| Proxmox host | -    | -    | ~2GB   | hypervisor                           |
| pihole       | LXC  | 1    | 0.375GB| LAN DNS + ad blocking, static IP     |
| postgres     | LXC  | 2    | 0.5GB  | NixOS Postgres service               |
| cloudflared  | LXC  | 1    | 0.25GB | tunnel to the Gateway                |
| k3s          | VM   | 4    | 8GB    | stateless web stack, Cilium, the apps |
| garage       | LXC  | 2    | 0.5GB  | S3 + static asset hosting            |
| media        | LXC  | 4    | 2GB    | Jellyfin + *arr + discovery          |
| ccflare      | LXC  | 2    | 2GB    | Anthropic/OpenAI proxy + dashboard   |
| vaultwarden  | LXC  | 1    | 0.375GB| Bitwarden-compatible password vault  |

These total 16GB exactly, so 0GB nominally free at rest (CI runners are
ephemeral ARC pods, zero at rest). Actual idle usage sits well under most of
these `dedicated` figures, but the budgeted total is now flush against the
16GB wall: lean on swap (`vm.swappiness=10`), stop a heavy on-demand box, or
trim one guest's `dedicated` if it's tight.

On-demand guests, not autostarted, so ~0 RAM at rest; start one when you need it:

| Guest             | Type | vCPU | RAM | Role                       |
|-------------------|------|------|-----|----------------------------|
| admin             | LXC  | 2    | 1GB | NixOS break-glass shell    |
| ai                | LXC  | 2    | 2GB | NixOS AI sandbox, isolated |
| playground        | LXC  | 2    | 2GB | NixOS scratch box          |
| playground-debian | LXC  | 2    | 2GB | Debian scratch box         |

With only ~1.5GB free we're at the 16GB wall, so run one heavy on-demand box at a
time. A few GB of SSD swap (or zram, `vm.swappiness=10`) absorbs spikes, but don't
let the latency-sensitive boxes (k3s, postgres, redis) actually swap.

## Network

Wired gigabit ethernet into a Fritz!Box. LAN is `192.168.178.0/24`, gateway
`192.168.178.1`. The Proxmox host is pinned to `192.168.178.100` (set in the
install answer file, Layer 0-1, not by OpenTofu).

| Address           | Host                                        |
|-------------------|---------------------------------------------|
| `.1`              | router (Fritz!Box)                          |
| `.100`            | Proxmox host                                |
| `.101`            | pihole (LXC)                                |
| `.102`            | postgres (LXC)                              |
| `.103`            | cloudflared (LXC)                           |
| `.104`            | k3s VM                                       |
| `.105`            | admin (LXC, NixOS) - break-glass shell      |
| `.107`            | playground (LXC, NixOS) - scratch box       |
| `.108`            | playground-debian (LXC, Debian) - scratch box |
| `.109`            | garage (LXC, NixOS) - S3 + static hosting   |
| `.110`            | media (LXC, NixOS) - Jellyfin + *arr + scripts |
| `.111`            | ccflare (LXC, NixOS) - Anthropic/OpenAI proxy  |
| `.112`            | vaultwarden (LXC, NixOS) - password vault   |
| `.200` - `.220`   | Cilium LB pool (.200 pinned to the Gateway) |

The `ai` sandbox is deliberately **not** on this LAN. It lives alone on an
internal NAT bridge (`vmbr1`, `10.10.10.0/24`, the box at `10.10.10.10`) so the
host can give it internet but block the LAN and other guests. See `nix/README.md`.

Two Fritz!Box-side steps once Pi-hole is up: reserve `.100` for the host in the
DHCP table (so the box keeps its address), and point the Fritz!Box DNS at the
Pi-hole IP so the whole LAN uses it.

The home Wi-Fi is set up as a host-only fallback uplink via
`bootstrap/host-network/wifi-setup.sh` (SSID + PSK from the env). The wired link
stays primary, since Wi-Fi can't bridge the guest network.

## Decisions made (and why)

- **Proxmox over bare metal.** Separate machines I can snapshot, reboot, and rebuild
  on their own. ~2GB host overhead; CPU cost is nil (hardware virt).
- **LXC for the light services, a VM only for k3s.** LXC idles at the RAM of its app;
  k3s needs a VM since k8s fights LXC's kernel limits.
- **LVM-thin, not ZFS.** Single disk, no redundancy goal, so ZFS's ARC would just
  cost 1-2GB of RAM. LVM-thin is ~0 overhead and still snapshots.
- **k3s networking off, Cilium on.** Cilium replaces flannel/kube-proxy/ServiceLB/
  Traefik on eBPF (CNI, LB IPs, Gateway, policy). Keep CoreDNS, local-path,
  metrics-server. Matches what we run at work.
- **Postgres + cloudflared are NixOS services, outside the cluster.** `nixos-rebuild`
  installs and runs them (no hollow container). Postgres stays out of k3s for rebuild
  safety; apps reach it over the LAN. Secrets via sops-nix.
- **Admin + playground + ai are NixOS LXCs, on-demand.** Tooling lives in containers,
  not on the host, so the hypervisor stays clean. None autostart, so they reserve no
  RAM. The host SSH + web console is the break-glass behind them.
- **AI sandbox isolated on the host.** Untrusted box (claude-code, codex, headless
  chromium): internet yes, LAN no, enforced on the host since the AI may have root
  in its own container. See `bootstrap/host-network/`.
- **Nix hosts share modules.** `base.nix` + `dev.nix` + `sops.nix`; each host is a
  short file. AI CLIs track `nixpkgs-unstable`, the rest stays on stable.
- **Cloudflare owns public TLS, internal leg is HTTP.** Avoids TLS-in-TLS; the tunnel
  is already encrypted.
- **Public repo, secrets via SOPS + age.** Secrets are age-encrypted so public
  ciphertext is fine. The age key is the one out-of-band secret. gitleaks
  pre-commit guards against plaintext leaks.

## Layers

This repo is built in layers. The USB only owns the bottom two; everything above
lives here in git and is applied by a tool, so a rebuild is reflash + apply.

- **Layer 0-1: bare-metal install** (`bootstrap/`). Proxmox unattended install
  from a baked answer file, plus a tiny first-boot script that installs git and
  pulls this repo.
- **Layer 2: guests** (`tofu/`). OpenTofu + the bpg/proxmox provider declares the
  LXCs and the k3s VM, with cloud-init for per-guest setup.
- **Layer 3: GitOps** (`cluster/`). Argo CD pulls the cluster state: Cilium,
  cloudflared config, and the apps.

See each directory's README for detail.

## Bootstrap and secrets

The repo is public, so cloning needs no credential. The only secret a fresh box
needs is the age private key. After the USB install:

1. SSH into the host at `192.168.178.100`, clone the repo.
2. Run `bootstrap/bootstrap.sh`. It reads the age key from a silent prompt (not a
   command argument, so it never hits shell history or `ps`), installs it where
   sops looks, checks it can decrypt, then launches Layers 2 and 3 detached.
3. Disconnect. The pipeline finishes on its own.

Reinstalling is reflash the stock USB, paste the age key once, done. The age key
lives only on the box and in your own backup. It is the single root secret:
everything else, including a git token for pulling private repos (app source,
private manifests for Argo), lives encrypted in the env and is unlocked by it.
See `secrets/` for the SOPS layout.

## Validation

`make validate` runs the checks (each skips if its tool is missing): `tofu
validate` + `fmt`, `nix flake check`, `kubeconform` against the cluster
manifests (with the CRD catalog), `shellcheck`, and `actionlint`. CI runs the
full set on every push (`.github/workflows/validate.yml`), including the Nix on a
runner that has `nix`.
