# Layer 0-1: bare-metal install

This is the only part the USB stick owns: an unattended Proxmox install that
sets the host up to the point where you can SSH in and run `bootstrap.sh`.

## What's here

- `answer.toml` - the unattended install config (disk, network, keys). Secret-free
  template; the root password hash is filled in only at build time.
- `first-boot.sh` - tiny handoff baked into the ISO, run once on first boot. It
  drops a `homelab-bootstrap` helper and an motd so the first SSH login knows the
  next step. No secrets, nothing pulled over the network here.
- `build-iso.sh` - bakes the auto-install ISO from the official Proxmox ISO.
- `bootstrap.sh` - run by hand after first boot (installs the age key, decrypts
  secrets, applies Layer 2). See `DEPLOY.md`.

The host is pinned to `192.168.178.100/24`, gw `192.168.178.1`, filesystem
LVM-thin (ext4 layout), fqdn `proxmox.internal`. That `.100` is the address the
OpenTofu provider talks to (`pve_endpoint`).

## Build the ISO

Needs the official Proxmox ISO. Latest is 9.2-1; grab it and check it:

    curl -fLO https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso
    # compare against https://enterprise.proxmox.com/iso/SHA256SUMS
    shasum -a 256 proxmox-ve_9.2-1.iso

Then bake. `proxmox-auto-install-assistant` is Linux + amd64 only; on macOS the
script runs it in a Debian amd64 container, so you need docker (colima is fine).
It asks for the root password on a hidden prompt and bakes only the SHA-512 hash:

    ./bootstrap/build-iso.sh proxmox-ve_9.2-1.iso

Output is `proxmox-ve_9.2-1-auto.iso`. That ISO is bootable and carries the
answer file + first-boot script, so it installs with no keyboard input.

## Flash to USB

The baked file is a hybrid ISO; write it raw to the stick (this wipes the stick).

Windows (the box currently runs Windows, and can take a USB):

- Rufus: pick the ISO, and when it asks, choose **DD image mode** (not ISO mode),
  then Start. Or balenaEtcher, which always writes raw.

Linux/macOS-with-USB, for reference:

    sudo dd if=proxmox-ve_9.2-1-auto.iso of=/dev/sdX bs=4M status=progress oflag=sync

## The age key stick (this is what makes it walk-away)

The install is unattended AND `first-boot.sh` runs `bootstrap.sh` on its own, so
there's no SSH and no key to paste. For that, first-boot needs the age *private*
key, which is deliberately NOT in the ISO (the ISO is shareable). Put it on a
small separate volume it can read:

- format a second USB stick (or a spare partition) as FAT32, volume label
  **`HOMELAB`**, and copy your age private key onto it as the file **`age.key`**.

At first boot the host finds the `HOMELAB` volume (`blkid -L HOMELAB`), copies
`age.key` into RAM, releases the stick, and hands it to `bootstrap.sh` on stdin,
which shreds it when done. The key never lands on disk or in the ISO.

## Boot it

Boot the box from the install stick with the `HOMELAB` key stick also plugged in.
It installs Proxmox unattended, reboots, and on first boot runs the whole Layer
0-2 pipeline itself (tofu guests + NixOS apply). Watch it, if you want, at
`/var/log/homelab-first-boot.log` and `/var/log/homelab-bootstrap.log`.

Two one-time notes so it truly walks away:

- Set the **internal NVMe first** in the BIOS boot order (or pull the install
  stick once the OS starts booting), so a later reboot doesn't re-run the
  installer and wipe the disk.
- Keep the `HOMELAB` key stick in until first boot has read it; then remove it.

If the auto run fails, the box still has the `homelab-bootstrap` helper + an motd
pointing at the logs, so you can finish it by hand.

## Secrets rule

Nothing decryptable is baked into the ISO. The only credentials in the image are
the root password hash and the homelab SSH public key. The age private key rides
the separate `HOMELAB` stick; everything else is SOPS-encrypted in git and
decrypted with that key. A rebuild is: reflash the same generic stick, plug the
key stick, boot.
