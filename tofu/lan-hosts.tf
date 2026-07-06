# Keep every host's /etc/hosts and Pi-hole's DNS records in sync with
# nix/lan-hosts automatically. Previously this needed someone to remember to
# re-run scripts/inject-hosts.sh + scripts/pihole-setup.sh by hand after
# editing the file -- missed once for real: a rename to ap.k3s.internal sat
# unapplied in Pi-hole for a while, so the old name kept resolving.
#
# Triggered by the file's content hash, so this only re-runs (on the next
# `tofu apply`) when nix/lan-hosts actually changed, not on every apply. Both
# scripts are idempotent, safe to re-run.
resource "null_resource" "lan_hosts_sync" {
  triggers = {
    lan_hosts_hash = filemd5("${path.module}/../nix/lan-hosts")
  }

  provisioner "local-exec" {
    command = "${path.module}/../scripts/inject-hosts.sh && ${path.module}/../scripts/pihole-setup.sh"
  }

  depends_on = [
    proxmox_virtual_environment_container.pihole,
    proxmox_virtual_environment_vm.k3s,
  ]
}
