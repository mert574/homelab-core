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
    fuse    = true # mergerfs (FUSE) pool for /srv; see nix/hosts/media.nix
  }

  # The 114G USB is bind-mounted into the CT as the second mergerfs branch. A tofu
  # `mount_point {}` block is ForceNew (would destroy the CT + rootfs), so the bind
  # mount is applied out-of-band with:
  #   pct set 110 --mp0 /mnt/media-usb-110,mp=/mnt/disk-usb,backup=0
  # and ignored here so tofu never tries to reconcile (and recreate) it.
  lifecycle {
    ignore_changes = [mount_point]
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 2048
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 108 # media fills fast
  }

  network_interface {
    name = "eth0"
  }

  # Intel iGPU (QuickSync) passthrough for Jellyfin hardware transcoding.
  device_passthrough {
    path = "/dev/dri/renderD128"
  }

  # /dev/net/tun so WireGuard (the qbittorrent VPN netns) works in the
  # unprivileged container.
  device_passthrough {
    path = "/dev/net/tun"
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
