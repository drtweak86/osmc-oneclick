#!/usr/bin/env bash
set -euo pipefail

STATE=/var/lib/oneclick
LOG=/var/log/oneclick-stage2.log
mkdir -p "$STATE"

echo "stage2: $(date -Is)" >> "$LOG"

# Wait for working network (up to ~60s)
for i in {1..30}; do
  if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 || ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# ==== YOUR REAL WORK STARTS HERE ====
# examples:
# /usr/local/sbin/wg-autoboot-fast --prime   || true
# systemctl enable --now batnet-vpn-unlock.service || true
# systemctl enable --now surfshark-wg.service     || true
# any hardening, assets, tuneables, etc.

# on-screen completion
if command -v kodi-send >/dev/null 2>&1; then
  kodi-send --action="Notification(Xtreme Setup,Optimisations complete. Enjoy!,8000)"
fi

touch "$STATE/done"
exit 0
