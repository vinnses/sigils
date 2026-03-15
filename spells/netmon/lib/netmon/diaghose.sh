#!/usr/bin/env bash

set -euo pipefail

OUT="${1:-network_diagnose_$(hostname)_$(date +%Y%m%d_%H%M%S).txt}"

exec > >(tee "$OUT") 2>&1

echo "=============================="
echo "NETWORK DIAGNOSTIC REPORT"
echo "Host: $(hostname)"
echo "Date: $(date -Is)"
echo "Kernel: $(uname -r)"
echo "=============================="
echo

section() {
  echo
  echo "--------------------------------"
  echo "$1"
  echo "--------------------------------"
}

section "1. Interfaces (link layer)"
ip -details link show

section "2. Interfaces (IP layer)"
ip addr show

section "3. Routing"
ip route show
ip -6 route show

section "4. Hardware overview (lshw)"
sudo lshw -C network || echo "lshw failed (permissions?)"

section "5. PCI devices (network)"
lspci -nn | grep -i network || true

section "6. PCI devices + drivers"
sudo lspci -k -nn | grep -A3 -i network || true

section "7. USB network devices"
lsusb || true

section "8. Ethernet details (ethtool)"
for iface in $(ls /sys/class/net); do
  if [[ -d "/sys/class/net/$iface/device" ]] && ethtool "$iface" &>/dev/null; then
    echo
    echo ">>> Interface: $iface"
    sudo ethtool "$iface"
  fi
done

section "9. Wi-Fi interfaces (iw dev)"
iw dev || echo "iw not available"

section "10. Wi-Fi hardware capabilities (iw list)"
iw list || echo "iw not available"

section "11. Wi-Fi link state"
for iface in $(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'); do
  echo
  echo ">>> Interface: $iface"
  iw dev "$iface" link
done

section "12. NetworkManager (nmcli)"
nmcli device show || echo "NetworkManager not available"

section "13. Firmware messages (dmesg)"
dmesg | grep -iE 'firmware|wifi|wlan|eth' || true

section "14. Loaded kernel modules (network-related)"
lsmod | grep -iE 'eth|wifi|wlan|80211|iwl|rtw|ath|brcm' || true

echo
echo "=============================="
echo "END OF REPORT"
echo "Output file: $OUT"
echo "=============================="

