# Mixed-use / media box (NixOS, ../nix/hosts/media.nix). Jellyfin + *arr + a
# Mullvad-confined torrent client. Always on (the TV reaches it on the LAN).
#
# Note: the torrent client uses WireGuard in a netns. In an unprivileged LXC that
# may need /dev/net/tun passed in (or running privileged); see DEPLOY.md.

resource "proxmox_virtual_environment_container" "media" {
  node_name = var.pve_node
  vm_id     = 110

  description  = "Media + scripts (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.datastore
    size         = 64 # media fills fast; see DEPLOY.md (storage)
  }

  network_interface {
    name = "eth0"
  }

  # Intel iGPU (QuickSync) passthrough for Jellyfin hardware transcoding.
  device_passthrough {
    path = "/dev/dri/renderD128"
  }

  initialization {
    hostname = "media"

    ip_config {
      ipv4 {
        address = var.media_ip
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
    order = 4
  }
}
