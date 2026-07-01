# AI sandbox (NixOS LXC, ../nix/hosts/ai.nix). Isolated on its own NAT bridge
# (vmbr1): internet yes, LAN no, enforced on the host since the AI may have root
# here (see bootstrap/host-network/). Unprivileged, on-demand.

resource "proxmox_virtual_environment_container" "ai" {
  node_name = var.pve_node
  vm_id     = 106

  description  = "AI sandbox (NixOS, network-isolated, managed by homelab-core)"
  unprivileged = true
  started      = false # on-demand; not autostarted

  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 20
  }

  network_interface {
    name   = "eth0"
    bridge = var.ai_bridge # vmbr1, the isolated internal NAT bridge
  }

  initialization {
    hostname = "ai"

    ip_config {
      ipv4 {
        address = var.ai_ip
        gateway = var.ai_gateway
      }
    }
  }

  operating_system {
    template_file_id = var.nixos_ct_template
    type             = "unmanaged"
  }
}
