# Proxmox connection
variable "pve_endpoint" {
  type        = string
  description = "Proxmox API URL. The host is pinned to 192.168.178.100 at install time."
  default     = "https://192.168.178.100:8006/"
}

variable "pve_api_token" {
  type        = string
  description = "Proxmox API token in the form USER@REALM!TOKENID=SECRET"
  sensitive   = true
}

variable "pve_node" {
  type        = string
  description = "Proxmox node name (hostname of the box)"
  default     = "pve"
}

variable "datastore" {
  type        = string
  description = "Storage where guest disks live (LVM-thin pool)"
  default     = "local-lvm"
}

# LAN
variable "lan_gateway" {
  type        = string
  description = "LAN default gateway (the Fritz!Box router)"
  default     = "192.168.178.1"
}

variable "lan_cidr_suffix" {
  type        = string
  description = "CIDR suffix for static IPs, e.g. 24 for a /24"
  default     = "24"
}

# Auth pushed into guests
variable "ssh_public_key" {
  type        = string
  description = "Public key authorized on every guest"
}

variable "ct_root_password" {
  type        = string
  description = "Root password for LXC containers (login is via SSH key; this is a fallback)"
  sensitive   = true
}

# Container OS template for the lone Debian guest (pihole). Download once on the
# node; confirm the current point release with `pveam available | grep debian-13`,
# then `pveam download local debian-13-standard_13.x-1_amd64.tar.zst`.
variable "debian_ct_template" {
  type        = string
  description = "Volume id of the Debian LXC template (pihole only)"
  default     = "local:vztmpl/debian-13-standard_13.1-1_amd64.tar.zst"
}

# Per-guest static IPs (host part only is fine to vary). Full address with suffix.
variable "pihole_ip" {
  type        = string
  description = "Static IPv4 for the Pi-hole container"
  default     = "192.168.178.101/24"
}

variable "postgres_ip" {
  type        = string
  description = "Static IPv4 for the Postgres container"
  default     = "192.168.178.102/24"
}

variable "cloudflared_ip" {
  type        = string
  description = "Static IPv4 for the cloudflared container"
  default     = "192.168.178.103/24"
}

variable "k3s_ip" {
  type        = string
  description = "Static IPv4 for the k3s VM"
  default     = "192.168.178.104/24"
}

variable "admin_ip" {
  type        = string
  description = "Static IPv4 for the admin LXC"
  default     = "192.168.178.105/24"
}

variable "playground_ip" {
  type        = string
  description = "Static IPv4 for the NixOS playground LXC"
  default     = "192.168.178.107/24"
}

variable "playground_debian_ip" {
  type        = string
  description = "Static IPv4 for the Debian playground LXC"
  default     = "192.168.178.108/24"
}

variable "garage_ip" {
  type        = string
  description = "Static IPv4 for the Garage object storage LXC"
  default     = "192.168.178.109/24"
}

variable "media_ip" {
  type        = string
  description = "Static IPv4 for the media / mixed-use LXC"
  default     = "192.168.178.110/24"
}


# NixOS LXC template, shared by the admin and ai boxes. Proxmox ships no NixOS
# template, so build one with nixos-generators (-f proxmox-lxc) or grab a prebuilt
# image from Hydra, upload it to local:vztmpl, then point this at it. See
# nix/README.md.
variable "nixos_ct_template" {
  type        = string
  description = "Volume id of the NixOS LXC template"
  default     = "local:vztmpl/nixos-proxmox-lxc.tar.xz"
}

# AI sandbox network. The ai box sits alone on an internal NAT bridge so the host
# can let it reach the internet while blocking the LAN and other guests. See
# nix/README.md for the host-side bridge + firewall config.
variable "ai_bridge" {
  type        = string
  description = "Proxmox bridge for the isolated AI container"
  default     = "vmbr1"
}

variable "ai_ip" {
  type        = string
  description = "Static IPv4 for the AI container on the isolated bridge"
  default     = "10.10.10.10/24"
}

variable "ai_gateway" {
  type        = string
  description = "Gateway for the AI container (the host vmbr1 address that NATs out)"
  default     = "10.10.10.1"
}
