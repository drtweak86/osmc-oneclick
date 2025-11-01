#!/usr/bin/env bash
# batnet-roast.sh — quick system “roast” log for network, VPN, and mounts

set -euo pipefail
LOG="/var/log/batnet-roast.log"

{
  echo "=== 🦇 BatNet Roast ($(date '+%F %T')) ==="

  echo "--- Network ---"
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show | grep -E "inet " || echo "No IPv4 address"
  else
    echo "ip command missing"
  fi

  echo "--- VPN (WireGuard) ---"
  if command -v wg >/dev/null 2>&1; then
    wg show || echo "No WireGuard interfaces"
  else
    echo "WireGuard not installed"
  fi

  echo "--- Mounts (vault) ---"
  mount | grep -E '/etc/batnet-vpn(\s|$)' || echo "VPN vault not mounted"

  echo "--- System uptime ---"
  uptime || echo "uptime unavailable"

  echo "=== End Roast ==="
  echo
} >>"$LOG" 2>&1
