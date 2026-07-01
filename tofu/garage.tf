# Garage object storage + static website host (NixOS, ../nix/hosts/garage.nix).
# Shared infra, always on. Apps push assets over S3 (3900); cloudflared serves
# sites from the web port (3902).

resource "proxmox_virtual_environment_container" "garage" {
  node_name = var.pve_node
  vm_id     = 109

  description  = "Garage S3 + static hosting (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1024
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 30
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "garage"

    ip_config {
      ipv4 {
        address = var.garage_ip
        gateway = var.lan_gateway
      }
    }
    # user + SSH key come from ../nix/modules/base.nix.
  }

  operating_system {
    template_file_id = var.nixos_ct_template
    type             = "unmanaged"
  }

  startup {
    order = 2
  }
}
