# Postgres in a NixOS LXC, kept out of k3s (rebuild safety); apps reach it over the
# LAN. Service is declared in ../nix/hosts/postgres.nix. 512MB to start, live-
# resizable if it OOMs.

resource "proxmox_virtual_environment_container" "postgres" {
  node_name = var.pve_node
  vm_id     = 102

  description  = "Postgres (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 512
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 20
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "postgres"

    ip_config {
      ipv4 {
        address = var.postgres_ip
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
    order = 2
  }
}
