# host-network

Isolated `vmbr1` bridge for the `ai` container: internet yes, LAN no. Enforced on
the host because the ai box is untrusted. Run `install.sh` on the Proxmox host
(must exist before `tofu apply` brings up the ai container).

- `vmbr1` -> `/etc/network/interfaces.d/` (bridge + NAT + drop rules)
- `99-homelab-ip-forward.conf` -> `/etc/sysctl.d/` (ip forwarding)
- `wifi-setup.sh` -> host-only Wi-Fi fallback uplink (SSID + PSK from `WIFI_SSID`
  / `WIFI_PSK` in the env). Wired stays primary; Wi-Fi can't bridge the guests, so
  it only keeps the host reachable. Set `WIFI_IFACE` to the real device.

Manage host networking through this repo, not the Proxmox web UI, or the UI may
drop the bridge. The drop rules insert at the top of FORWARD, so they hold with
pve-firewall on or off.
