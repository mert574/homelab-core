# NixOS LXC hosts

The NixOS containers, declared once and reused.

```
nix/
  flake.nix          # nixosConfigurations: admin, ai, playground, postgres, cloudflared
  modules/
    base.nix         # shared: proxmox-lxc, ssh, user, zsh, base CLI kit, pbcopy
    dev.nix          # full dev + cloud/k8s kit (admin, playground)
    sops.nix         # sops-nix secret decryption (postgres, cloudflared)
  hosts/
    *.nix            # one per box: imports modules + its own packages
```

Hosts import `base.nix` (plus `dev.nix`/`sops.nix` as needed) and add a few
packages. The flake passes a `nixpkgs-unstable` input to `ai` for the fast-moving
AI CLIs; everything else stays on stable (`nixos-26.05`).

## NixOS LXC template

Proxmox ships none, so provide one (used via `var.nixos_ct_template`):

- build with nixos-generators (needs a Linux Nix builder):
  `nix run github:nix-community/nixos-generators -- -f proxmox-lxc -o ./result`,
  then upload the `.tar.xz` to `local:vztmpl`; or
- download a prebuilt `proxmox-lxc` image from Hydra.

## Applying a host

```sh
nixos-rebuild switch --flake .#admin   # or ai / playground / postgres / cloudflared
```

## Notes

- AI isolation (host-enforced) lives in `bootstrap/host-network/`; run its
  `install.sh` on the host before bringing up the ai box.
- Secrets need the per-host age keys added to `.sops.yaml` after first boot
  (see `modules/sops.nix`).
- `opencode` / `codex` come from unstable; bump the input if your pin lacks one.
- First boot: if a box has no IP, the template ignored Proxmox's static IP, set
  `proxmoxLXC.manageNetwork` and declare it in nix.
