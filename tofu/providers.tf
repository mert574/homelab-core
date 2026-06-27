provider "proxmox" {
  endpoint = var.pve_endpoint # https://192.168.178.100:8006/

  # Use an API token, not a password. Create one in Proxmox under
  # Datacenter > Permissions > API Tokens and give it the roles it needs.
  api_token = var.pve_api_token

  # Single home node with a self-signed cert.
  insecure = true

  # Some bpg resources (file uploads, container templates) need SSH to the node.
  ssh {
    agent    = true
    username = "root"
  }
}
