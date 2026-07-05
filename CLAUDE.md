# homelab-core notes

## Secrets (secrets/homelab.enc.env)

- It's a sops-encrypted dotenv where EVERY value is quoted: `KEY="value"`.
- Anything that reads it must strip the surrounding quotes. `scripts/load-env.sh`
  does this on the host, and the guest-side extractors do the same (see the
  garage-secrets service in `nix/hosts/garage.nix`).
- Never load it with `eval` or plain `source`-style parsing assumptions: values
  contain spaces (the SSH key) and `=` signs. A parser that exports the raw
  value ships the quotes into the value, which breaks consumers (the PVE
  provider 401s on a quoted password).

## Applying changes

- Nothing applies automatically. Argo CD only syncs `cluster/` (k8s manifests).
  The tofu layer and the NixOS hosts are applied by hand from the Proxmox host.
- `tofu` runs on the Proxmox host as root: `. scripts/load-env.sh`, then
  `tofu -chdir=tofu plan|apply`.
- Cloud-init changes to a VM (e.g. `initialization` in `tofu/k3s.tf`) only take
  effect after the VM reboots.

## LAN names

- `nix/lan-hosts` is the single source of truth for `.internal` names. NixOS
  guests get it via `networking.extraHosts`; everything else via
  `scripts/inject-hosts.sh`; pi-hole serves the same records as DNS
  (`scripts/pihole-setup.sh`).
- Pods on k3s only resolve `.internal` through DNS (CoreDNS -> node resolver ->
  pi-hole), never through /etc/hosts.
