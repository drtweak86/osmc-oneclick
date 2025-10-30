#!/usr/bin/env bash
LOG="/var/log/batnet-roast.log"
{
  echo "=== BatNet Roast ==="
  date
  echo "--- Network ---"
  ip -4 addr show | grep -E "inet " || echo "No IPv4 address"
  echo "--- VPN (WireGuard) ---"
  if command -v wg >/dev/null 2>&1; then
    wg show || echo "No WireGuard interfaces"
  else
    echo "WireGuard not installed"
  fi
  echo "--- Mounts (vault) ---"
  mount | grep -E '/etc/batnet-vpn(\s|$)' || echo "VPN vault not mounted"
  echo "=== End Roast ==="
} >>"$LOG" 2>&1
