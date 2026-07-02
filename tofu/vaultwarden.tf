# Vaultwarden: self-hosted Bitwarden-compatible password manager (NixOS,
# ../nix/hosts/vaultwarden.nix). The least-disposable thing here (it holds the
# vault), so it's its own always-on LXC, kept out of k3s so a cluster rebuild
# never touches its data. State (SQLite DB + attachments + keys) persists under
# /var/lib/bitwarden_rs in the CT. Public at https://pw.mert574.dev via the
# cloudflared tunnel; the server listens on :8000.

resource "proxmox_virtual_environment_container" "vaultwarden" {
  node_name = var.pve_node
  vm_id     = 112

  description  = "Vaultwarden password manager (NixOS, managed by homelab-core)"
  unprivileged = true

  features {
    nesting = true
  }

  cpu {
    cores = 1
  }

  memory {
    # Vaultwarden (Rust) idles ~50-100MB; 384 is ample. We're at the 16GB wall,
    # so keep dedicated small and give it generous swap (matches postgres/garage)
    # to absorb spikes and first-build memory pressure.
    dedicated = 384
    swap      = 4096
  }

  disk {
    datastore_id = var.datastore
    size         = 8
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "vaultwarden"

    ip_config {
      ipv4 {
        address = var.vaultwarden_ip
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
