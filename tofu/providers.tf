provider "proxmox" {
  endpoint = var.pve_endpoint # https://192.168.178.100:8006/

  # root@pam + the root password baked into the install, so there's no manual
  # "create an API token in the UI" step. That's what makes the bootstrap
  # walk-away: tofu runs on the freshly installed host and logs in as root.
  username = var.pve_username # root@pam
  password = var.pve_password # from TF_VAR_pve_password (sops env)

  # Single home node with a self-signed cert.
  insecure = true

  # Some bpg resources (snippets, cloud image import for the k3s VM) need SSH to
  # the node. tofu runs on the host, so this is root SSHing to itself with a key
  # bootstrap.sh generates. No agent: there's no login shell / SSH_AUTH_SOCK.
  ssh {
    agent       = false
    username    = "root"
    private_key = file(var.pve_ssh_private_key_file)
  }
}
