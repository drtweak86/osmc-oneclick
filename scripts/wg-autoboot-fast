#!/usr/bin/env bash
# scripts/wg-autoboot-fast
set -euo pipefail

CONF_DIR="/etc/batnet-vpn"  # decrypted mount from gocryptfs

# If something is already up, do nothing (your other selector might have started it)
if wg show interfaces >/dev/null 2>&1 && [ -n "$(wg show interfaces)" ]; then
  echo "WireGuard already up; skipping autoboot selection."
  exit 0
fi

best_conf=""
best_ms=999999

for f in "$CONF_DIR"/*.conf; do
  [ -e "$f" ] || continue
  ep=$(awk -F= '/^Endpoint[[:space:]]*=/{gsub(/[[:space:]]/,"",$2);print $2; exit}' "$f") || true
  host="${ep%%:*}"
  [ -n "$host" ] || continue
  ip=$(getent ahosts "$host" | awk 'NR==1{print $1}')
  [ -n "$ip" ] || continue

  # Quick latency probe: 2 pings, 1s timeout
  ms=$(ping -c 2 -W 1 "$ip" 2>/dev/null | awk -F'[=/]' '/^rtt|^round-trip/{print $5}')
  [ -n "$ms" ] || ms=999999
  printf "BOOT-TEST  %-30s %8.2f ms\n" "$(basename "$f")" "$ms"

  awk -v a="$ms" -v b="$best_ms" 'BEGIN{exit !(a<b)}' && { best_ms="$ms"; best_conf="$f"; }
done

[ -z "$best_conf" ] && { echo "No Surfshark configs found."; exit 1; }

echo "BOOT-SELECT → $(basename "$best_conf") (${best_ms}ms)"
/usr/bin/wg-quick up "$best_conf"
