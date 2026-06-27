# Admin / break-glass shell (NixOS LXC, declared in ../nix/hosts/admin.nix). The
# box you SSH into to manage the cluster and guests. On-demand (no RAM at rest).
# Note: pct/qm are host-only, so hypervisor recovery is still SSH to the host.

resource "proxmox_virtual_environment_container" "admin" {
  node_name = var.pve_node
  vm_id     = 105

  description  = "Admin / break-glass shell (NixOS, managed by homelab-core)"
  unprivileged = true
  started      = false # on-demand; not autostarted

  # NixOS LXC wants nesting on.
  features {
    nesting = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = var.datastore
    size         = 16
  }

  network_interface {
    name = "eth0"
  }

  initialization {
    hostname = "admin"

    ip_config {
      ipv4 {
        address = var.admin_ip
        gateway = var.lan_gateway
      }
    }
    # No user_account here: the NixOS image has no cloud-init user setup. The
    # user and SSH key come from ../nix/hosts/admin.nix (via ../nix/modules/base.nix).
  }

  operating_system {
    template_file_id = var.nixos_ct_template
    type             = "unmanaged"
  }

  startup {
    order = 3
  }
}
