# cloudflared in a NixOS LXC so the tunnel stays up across cluster rebuilds.
# Service is declared in ../nix/hosts/cloudflared.nix (token from the encrypted
# env). Points at the Cilium Gateway; Cloudflare owns public TLS. Moves in-cluster later.

resource "proxmox_virtual_environment_container" "cloudflared" {
  node_name = var.pve_node
  vm_id     = 103

  description  = "Cloudflare tunnel (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 256
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "cloudflared"

    ip_config {
      ipv4 {
        address = var.cloudflared_ip
        gateway = var.lan_gateway
      }
    }
    # No user_account: the user and SSH key come from ../nix/modules/base.nix.
  }

  operating_system {
    template_file_id = var.nixos_ct_template
    type             = "unmanaged"
  }

  startup {
    order = 4
  }
}
