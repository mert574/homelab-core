# Layer 2: guests (OpenTofu)

Declares the LXC containers and the k3s VM on Proxmox with the `bpg/proxmox`
provider. cloud-init / LXC init handles per-guest setup.

## What's here

- `versions.tf` - provider + version pins
- `providers.tf` - Proxmox connection (API token + SSH to the node)
- `variables.tf` - inputs (connection, LAN, per-guest IPs)
- `pihole.tf` - Pi-hole LXC (`.101`)
- `postgres.tf` - Postgres LXC (`.102`, 512MB)
- `cloudflared.tf` - Cloudflare tunnel LXC (`.103`)
- `k3s.tf` - the k3s VM (`.104`) + Debian cloud image + cloud-init
- `admin.tf` - NixOS admin LXC (`.105`, on-demand)
- `ai.tf` - isolated NixOS AI sandbox (`10.10.10.10`, on-demand)
- `terraform.tfvars.example` - copy to `terraform.tfvars` and fill in

The k3s VM installs k3s via cloud-init (`../cloud-init/k3s.yaml.tftpl`) with
flannel/kube-proxy/servicelb/traefik disabled so Cilium owns networking. The
Debian LXC apps (Postgres, cloudflared) are installed by a provisioning step, not
cloud-init, since Proxmox LXC has no runcmd.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars   # then edit
tofu init
tofu plan
tofu apply
```

## One-time prep on the Proxmox node

- Create the API token used in `pve_api_token` (Datacenter > Permissions > API
  Tokens) and give its user the roles to manage VMs/containers and storage.
- Download a Debian LXC template once so containers can be created from it:
  `pveam update && pveam download local debian-12-standard_12.7-1_amd64.tar.zst`

## Notes

- `terraform.tfvars` and `*.tfstate` are gitignored. State is local for now;
  move it to a backend later if this grows.
- The k3s VM gets created here, but its k3s install flags (disable flannel,
  kube-proxy, servicelb, traefik so Cilium can take over) run via cloud-init.
  The Cilium install and everything above it is Layer 3 (`../cluster`).
