#!/usr/bin/env bash
# Configure the host's Wi-Fi as a fallback uplink. The wired link stays primary;
# Wi-Fi only carries the host itself (it can't bridge the guest network). Run on
# the Proxmox host with WIFI_PSK set from the decrypted env.
#
#   WIFI_IFACE=wlp1s0 ./wifi-setup.sh   (find the device with: ip link)
set -euo pipefail
: "${WIFI_SSID:?set WIFI_SSID (from the encrypted env) before running}"
: "${WIFI_PSK:?set WIFI_PSK (from the encrypted env) before running}"
IFACE="${WIFI_IFACE:-wlan0}"

apt-get install -y wpasupplicant

# SSID + PSK come from the env; channel is not set (it changes; wpa_supplicant
# scans for it). WPA2/WPA3 transition: plaintext psk works for both, ieee80211w=1
# for SAE.
conf="/etc/wpa_supplicant/wpa_supplicant-${IFACE}.conf"
install -m 600 /dev/null "$conf"
cat > "$conf" <<EOF
ctrl_interface=/run/wpa_supplicant
country=DE
network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PSK}"
    key_mgmt=WPA-PSK SAE
    ieee80211w=1
}
EOF

systemctl enable --now "wpa_supplicant@${IFACE}.service"

# DHCP on the wlan interface, host uplink only (no bridge)
cat > /etc/network/interfaces.d/wlan <<EOF
auto ${IFACE}
iface ${IFACE} inet dhcp
EOF
ifup "${IFACE}" 2>/dev/null || ifreload -a 2>/dev/null || true

echo "Wi-Fi fallback up on ${IFACE} (SSID ${WIFI_SSID})."
