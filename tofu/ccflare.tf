# ccflare: multi-account Anthropic/OpenAI proxy + dashboard (NixOS,
# ../nix/hosts/ccflare.nix). Load-balances requests across several Claude/OpenAI
# accounts and keeps request history + analytics. Always on; proxy + dashboard on
# :8080. State (SQLite DB + config) persists under /var/lib/ccflare in the CT.

resource "proxmox_virtual_environment_container" "ccflare" {
  node_name = var.pve_node
  vm_id     = 111

  description  = "ccflare Anthropic/OpenAI proxy (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1536
    swap      = 2048
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "ccflare"

    ip_config {
      ipv4 {
        address = var.ccflare_ip
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
    order = 3
  }
}
