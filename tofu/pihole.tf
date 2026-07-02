# Pi-hole: LAN DNS in its own LXC, kept out of k3s so it stays up across cluster
# rebuilds. Point the router's DNS at pihole_ip once it's up.

resource "proxmox_virtual_environment_container" "pihole" {
  node_name = var.pve_node
  vm_id     = 101

  description  = "Pi-hole DNS + ad blocking (managed by homelab-core)"
  unprivileged = true

  # trixie's systemd 257 needs nesting on in an unprivileged container.
  features {
    nesting = true
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = var.datastore
    size         = 2 # pihole uses <1G; 2G is plenty
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "pihole"

    ip_config {
      ipv4 {
        address = var.pihole_ip
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

  # The template is only a create-time seed; never recreate this container just
  # because a newer Debian point release changed the volume id.
  lifecycle {
    ignore_changes = [operating_system]
  }

  # Start first on boot so the LAN has DNS before anything else comes up.
  startup {
    order = 1
  }
}
