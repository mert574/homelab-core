# bifrost: multi-account Anthropic/OpenAI gateway (NixOS, ../nix/hosts/bifrost.nix),
# replacing ccflare. Same job (credential pool, usage tracking, budget-based key
# rotation, OpenAI-compat adapter) as a single Go binary run via Docker, so it needs
# far less CPU/RAM than ccflare's Bun-workspace build. Proxy + dashboard on :8080.
# State (config.json + its SQLite config store) persists under /var/lib/bifrost in the CT.

resource "proxmox_virtual_environment_container" "bifrost" {
  node_name = var.pve_node
  vm_id     = 113

  description  = "Bifrost Anthropic/OpenAI proxy (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
    keyctl  = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 1024
  }

  disk {
    datastore_id = var.datastore
    size         = 12
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "bifrost"

    ip_config {
      ipv4 {
        address = var.bifrost_ip
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
