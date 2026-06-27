# k3s node in a VM (k8s fights LXC limits). cloud-init disables flannel/kube-proxy/
# servicelb/traefik so Cilium owns networking. Stateless and disposable.

# Debian cloud image, downloaded to the node once and imported as the VM disk.
resource "proxmox_download_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.pve_node
  url          = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  file_name    = "debian-13-genericcloud-amd64.img"
}

# cloud-init user-data: the k3s install with Cilium-ready flags. Templated so the
# SSH key is injected from the same var the other guests use.
resource "proxmox_virtual_environment_file" "k3s_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.pve_node

  source_raw {
    file_name = "k3s-cloud-init.yaml"
    data = templatefile("${path.module}/../cloud-init/k3s.yaml.tftpl", {
      ssh_public_key = var.ssh_public_key
    })
  }
}

resource "proxmox_virtual_environment_vm" "k3s" {
  node_name   = var.pve_node
  vm_id       = 104
  name        = "k3s"
  description = "k3s node, Cilium-ready (managed by homelab-core)"

  agent {
    enabled = true
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.datastore
    file_id      = proxmox_download_file.debian_cloud_image.id
    interface    = "scsi0"
    size         = 40
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.datastore

    ip_config {
      ipv4 {
        address = var.k3s_ip
        gateway = var.lan_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_cloud_init.id
  }

  operating_system {
    type = "l26"
  }

  startup {
    order = 5
  }
}
