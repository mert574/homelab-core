terraform {
  required_version = ">= 1.7"

  required_providers {
    # bpg/proxmox is the actively maintained Proxmox provider.
    # Telmate's is older and buggier, so we avoid it.
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
    # for the k3s_bootstrap local-exec provisioner (tofu/k3s.tf)
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
