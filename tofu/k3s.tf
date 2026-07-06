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

    # Pi-hole as the node's resolver so pods can resolve the .internal names
    # (CoreDNS forwards to the node's resolv.conf; pods never see /etc/hosts).
    # No public fallback on purpose: pihole starts first on boot (tofu/pihole.tf),
    # and a fallback would make .internal lookups flaky whenever it's picked.
    dns {
      servers = [split("/", var.pihole_ip)[0]]
    }

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

# Auto-bootstrap Layer 3 (cluster/bootstrap/up.sh: kubeconfig fetch, Gateway
# CRDs, Cilium, Argo CD, root app, per-app secrets) whenever this VM is applied.
# Runs on every apply, not just a replace -- every step up.sh does is idempotent
# (helm upgrade --install, kubectl apply, secret create --dry-run=client | apply),
# so a no-op run just costs a few seconds. This is what makes a VM recreate
# (e.g. from an unrelated cloud-init change forcing replacement) actually
# hands-off instead of needing someone to remember to run up.sh by hand -- which
# is exactly what didn't happen after the 2026-07-06 host-OOM incident forced
# a k3s VM recreate.
# Requires the caller to have sourced scripts/load-env.sh before `tofu apply`
# (same convention as running up.sh directly), so local-exec inherits
# GIT_HTTP_TOKEN / GITHUB_RUNNER_TOKEN / SOPS_AGE_KEY_FILE.
resource "null_resource" "k3s_bootstrap" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "${path.module}/../cluster/bootstrap/up.sh"
  }

  depends_on = [proxmox_virtual_environment_vm.k3s]
}
