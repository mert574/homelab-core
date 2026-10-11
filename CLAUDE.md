# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Infrastructure as code for a single-box homelab: one Proxmox host running NixOS
LXCs for stateful services, a k3s VM for the stateless apps (Cilium + Argo CD),
and a Cloudflare tunnel for public ingress. The repo is public; secrets are
sops + age encrypted. See `README.md` for hardware, RAM budget, and the
decisions-made rationale; `DEPLOY.md` is the full from-scratch setup checklist.

## Architecture: three layers, applied differently

1. **Layer 0-1, `bootstrap/`** - one-time bare-metal install (unattended
   Proxmox ISO + first-boot handoff). You don't touch this day to day; see
   `bootstrap/README.md` if rebuilding the box from scratch.
2. **Layer 2, `tofu/`** - OpenTofu (`bpg/proxmox` provider) declares every LXC
   and the k3s VM, one `.tf` file per guest. State is local (`*.tfstate`,
   gitignored), not a remote backend.
3. **Layer 3, `cluster/`** - GitOps. Argo CD's app-of-apps
   (`cluster/bootstrap/root-app.yaml`) watches `cluster/apps/` **on the `main`
   branch on GitHub**, with `prune: true` and `selfHeal: true`.

**Nothing applies automatically except Layer 3.** Layers 0-2 (tofu, NixOS
hosts) are applied by hand, from the Proxmox host, not from a dev machine. Only
Layer 3 reacts to a push on its own, and only to `main`, not to a local
checkout or working tree: deleting or editing a `cluster/apps/<name>/`
directory does nothing to the live cluster until it's pushed. A manual
`kubectl delete` on something still present in `main` gets undone by
self-heal.

## Host model

- Stateful services get their own always-on NixOS LXC, kept out of k3s, so a
  cluster rebuild never touches their data (`postgres`, `cloudflared`,
  `garage`, `media`, `vaultwarden`).
- k3s is a disposable VM. Cilium owns all cluster networking (CNI, LB IPAM, L2
  announcements, Gateway API) - no MetalLB, Traefik, kube-proxy, or flannel.
- `admin` and `ai` are on-demand NixOS LXCs, not autostarted; start them by
  hand when needed (`pct start <vmid>` from the Proxmox host).
- `ai` sits alone on an isolated bridge (`vmbr1`, `10.10.10.0/24`): internet
  out, no LAN in, host-enforced since it's the untrusted sandbox. It's the one
  host missing from `nix/lan-hosts`.
- Adding or removing a NixOS host touches several places that nothing keeps in
  sync automatically: `nix/hosts/<name>.nix`, `flake.nix`'s
  `nixosConfigurations`, the matching `tofu/<name>.tf` (+ its IP variable in
  `tofu/variables.tf`), `scripts/apply-nixos.sh`'s `hosts` array, `nix/lan-hosts`,
  and the host-list lines in `.github/workflows/validate.yml`. Grep for the old
  name across the repo before considering a host fully removed.

## Secrets

- sops + age. The one root secret is the age private key; it lives only on the
  Proxmox host (`/root/.config/sops/age/keys.txt`) and the owner's own backup,
  never in git.
- The main dotenv (`secrets/homelab.enc.env`) has every value quoted
  (`KEY="value"`). Anything that reads it must strip the quotes itself -
  `scripts/load-env.sh` is the reference implementation. Never load it with
  `eval` or a plain `source` assumption: values contain spaces (the SSH key)
  and `=` signs, and a parser that exports the raw value ships the quotes into
  the value (breaks consumers like the Proxmox provider's password).
- To just read a value: `sops -d secrets/homelab.enc.env`.

## Networking

- LAN is `192.168.178.0/24`. `nix/lan-hosts` is the single source of truth for
  `.internal` names: NixOS guests get it via `networking.extraHosts`,
  everything else via `scripts/inject-hosts.sh`, and Pi-hole serves the same
  records as DNS (`scripts/pihole-setup.sh`). k3s pods only resolve
  `.internal` through DNS (CoreDNS -> pi-hole), never through `/etc/hosts`.
- Public ingress: Cloudflare tunnel (`cloudflared` LXC) terminates TLS, then
  either hits a LAN IP:port directly (NixOS services) or the Cilium Gateway's
  pinned LB IP (`192.168.178.200`), which routes by Host header to the right
  k3s app's HTTPRoute. All of this is declared in `nix/hosts/cloudflared.nix`.
  The only manual Cloudflare-side steps are a DNS route per hostname
  (`cloudflared tunnel route dns`) and, for admin-only surfaces, a Cloudflare
  Access application - both are dashboard/API state, not in this repo, and
  don't get cleaned up just by removing the ingress line.

## Commands

- `make validate` runs everything CI runs: `tofu fmt -check` + `tofu validate`,
  `nix flake check`, kubeconform against `cluster/`, shellcheck on every
  `.sh`, and actionlint. Each step skips with a note if its tool isn't
  installed, so it degrades gracefully locally.
- Individual pieces: `make tofu`, `make nix`, `make k8s`, `make sh`, `make ci`.
- Apply a NixOS host, run on the Proxmox host as root:
  `scripts/apply-nixos.sh <hostname>` (no args applies all of them). It tars
  the repo and runs `nixos-rebuild switch` inside the container over
  `pct exec`. The repo copy it tars is whatever's checked out on the Proxmox
  host (commonly `/root/homelab-core`), not wherever you're editing - `git
  pull` it (or sync your edits over) before applying, it's a plain clone that
  nothing auto-updates.
- tofu, also run on the Proxmox host as root: `. scripts/load-env.sh`, then
  `tofu -chdir=tofu plan|apply`. Prefer scoping with `-target` unless you
  specifically want to reconcile every host: `null_resource.k3s_bootstrap`
  re-runs `cluster/bootstrap/up.sh` on literally every apply by design
  (`triggers.always_run = timestamp()`), and on-demand/always-on guests can
  be in a different power state than declared, which an untargeted apply will
  "fix" by stopping or starting them.
- Cloud-init changes to the k3s VM (e.g. `initialization` in `tofu/k3s.tf`)
  only take effect after the VM reboots.
