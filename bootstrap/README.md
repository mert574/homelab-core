# Layer 0-1: bare-metal install

This is the only part the USB stick owns.

The plan (from the design chat):

1. **Unattended Proxmox install.** Write an `answer.toml` (disk, filesystem =
   LVM-thin, network, root SSH key, timezone). Bake it into the official Proxmox
   ISO with `proxmox-auto-install-assistant`, producing a custom ISO. Write that
   to USB, boot the box, walk away. Proxmox 8.2+ supports this.

   Static network for the host, set here in `answer.toml`:
   - IP: `192.168.178.100/24`
   - gateway: `192.168.178.1`
   - this is the address the OpenTofu provider talks to (`pve_endpoint`).

2. **First-boot handoff.** Proxmox 8.3+ runs a first-boot script from the answer
   file. Keep it tiny: install git, pull this repo, and hand off to Layer 2.
   No secrets and nothing setup-specific live on the USB. A rebuild is reflash
   the same generic stick, then `tofu apply` + Argo CD.

Files to add here when we build it:

- `answer.toml` (or a template plus a small build script)
- `first-boot.sh`
- a short note on the `proxmox-auto-install-assistant` command to bake the ISO

Secrets rule: nothing decryptable goes on the USB. The tunnel token and
passwords come from SOPS-encrypted files in git, decrypted with a key supplied
at bootstrap.
