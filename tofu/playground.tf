# Playground: NixOS scratch box (full dev kit + ffmpeg, ../nix/hosts/playground.nix).
# Experiment and nuke freely. Unprivileged, on-demand. Debian twin: playground-debian.tf.

resource "proxmox_virtual_environment_container" "playground" {
  node_name = var.pve_node
  vm_id     = 107

  description  = "Playground scratch box (NixOS, managed by homelab-core)"
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
    name = "eth0"
  }

  initialization {
    hostname = "playground"

    ip_config {
      ipv4 {
        address = var.playground_ip
        gateway = var.lan_gateway
      }
    }
    # No user_account: the user and SSH key come from ../nix/modules/base.nix.
  }

  operating_system {
    template_file_id = var.nixos_ct_template
    type             = "unmanaged"
  }
}
