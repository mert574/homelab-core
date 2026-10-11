#!/usr/bin/env bash
# Install a systemd unit on the Proxmox host that lowers CPU power at every
# boot. Run on the Proxmox host as root.
#
# The i5-9500T has its voltage offset locked, so no undervolt. Instead we set
# the powersave governor with balance_power EPP (clocks drop when idle, turbo
# still works for heavy jobs) and cap the short-term power limit (PL2) at 45W.
# The board default for PL2 is 92W, far above the 35W part rating.
set -euo pipefail

PL2_UW=45000000

UNIT_PATH=/etc/systemd/system/cpu-power.service

cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Lower CPU power (powersave governor, EPP, PL2 cap)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for c in /sys/devices/system/cpu/cpu*/cpufreq; do echo powersave > \$c/scaling_governor; echo balance_power > \$c/energy_performance_preference; done'
ExecStart=/bin/sh -c 'echo $PL2_UW > /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cpu-power.service

echo "governor: $(sort -u /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | tr '\n' ' ')"
echo "epp: $(sort -u /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference | tr '\n' ' ')"
echo "PL2: $(( $(cat /sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw) / 1000000 ))W"
echo "done. settings are applied now and on every boot."
