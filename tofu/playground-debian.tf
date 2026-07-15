# Playground (Debian): a Debian counterpart of the NixOS playground scratch box.
# Unprivileged, on-demand. No cloud-init runcmd on LXC, so its toolset installs
# via ../scripts/playground-debian-setup.sh.

resource "proxmox_virtual_environment_container" "playground_debian" {
  node_name = var.pve_node
  vm_id     = 108

  description  = "Playground scratch box (Debian, managed by homelab-core)"
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
  }

  disk {
    datastore_id = var.datastore
    size         = 20
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "playground-debian"

    ip_config {
      ipv4 {
        address = var.playground_debian_ip
        gateway = var.lan_gateway
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = var.ct_root_password
    }
  }

  operating_system {
    template_file_id = var.debian_ct_template
    type             = "debian"
  }

  # Never recreate over a Debian point-release template drift.
  lifecycle {
    ignore_changes = [operating_system]
  }
}
