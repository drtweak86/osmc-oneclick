#!/usr/bin/env bash
# XBian Wi-Fi autoswitch: prefer strongest preferred SSIDs (no ConnMan, no systemd)
set -euo pipefail
log(){ echo "[oneclick][33_wifi_autoswitch] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

ASSETS_BASE="${ASSETS_BASE:-/opt/osmc-oneclick/assets}"
ASSET_CFG="${ASSETS_BASE}/config/wifi-autoswitch"
CONF="/etc/default/wifi-autoswitch"
BIN="/usr/local/sbin/wifi-autoswitch"
CRON="/etc/cron.d/wifi-autoswitch"

ensure_deps() {
  command -v wpa_cli >/dev/null 2>&1 || { warn "wpa_cli missing"; exit 0; }
  command -v iw >/dev/null 2>&1 || command -v iwgetid >/dev/null 2>&1 || {
    warn "iw/iwgetid missing"; exit 0; }
}

seed_conf() {
  if [[ ! -f "$CONF" && -f "$ASSET_CFG" ]]; then
    log "Seeding $CONF from assets"
    install -o root -g root -m 0644 "$ASSET_CFG" "$CONF"
  elif [[ ! -f "$CONF" ]]; then
    cat >"$CONF" <<'CFG'
# Space-separated list of preferred SSIDs (in order of preference)
PREFERRED_SSIDS="HomeWiFi UpstairsWiFi"
# Wireless interface
WIFI_IFACE="wlan0"
# Minimum RSSI (in dBm) to consider “good” (e.g., -70)
MIN_RSSI="-75"
# Notify in Kodi (if kodi-send exists): 0/1
KODI_NOTIFY=1
CFG
    chmod 0644 "$CONF"
  fi
}

install_worker() {
  # ensure target dir exists
  install -d -m 0755 /usr/local/sbin

  install -D -o root -g root -m 0755 /dev/stdin "$BIN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
CONF="/etc/default/wifi-autoswitch"
[ -r "$CONF" ] && . "$CONF"

WIFI_IFACE="${WIFI_IFACE:-wlan0}"
PREFERRED_SSIDS="${PREFERRED_SSIDS:-}"
MIN_RSSI="${MIN_RSSI:--75}"
KODI_NOTIFY="${KODI_NOTIFY:-1}"

notify() {
  local msg="$1"
  if [ "$KODI_NOTIFY" = "1" ] && command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(WiFi,${msg//,/},3500)" >/dev/null 2>&1 || true
  fi
  echo "[wifi-autoswitch] $msg"
}

# Build scan list: SSID → RSSI
declare -A RSSI
if command -v iw >/dev/null 2>&1; then
  while IFS= read -r line; do
    case "$line" in
      "BSS "*) cur="" ;;
      *"SSID: "*) ssid="${line#*SSID: }" ; cur="$ssid" ;;
      *"signal: "*) if [ -n "${cur:-}" ]; then
          rssi="${line#*signal: }"; rssi="${rssi%% *}"
          RSSI["$cur"]="${rssi%.*}"
        fi ;;
    esac
  done < <(iw dev "$WIFI_IFACE" scan 2>/dev/null || true)
fi

# Fallback: ensure we at least know current SSID
CUR_SSID="$(iwgetid -r 2>/dev/null || true)"
BEST_SSID=""
BEST_RSSI="-999"

for ssid in $PREFERRED_SSIDS; do
  r="${RSSI[$ssid]:--999}"
  # prefer by (1) presence, (2) strongest RSSI, (3) order in list
  if [ "$r" -gt "$BEST_RSSI" ]; then
    BEST_RSSI="$r"
    BEST_SSID="$ssid"
  fi
done

# If nothing better than threshold, do nothing
[ "$BEST_RSSI" -lt "$MIN_RSSI" ] && exit 0

# Already on best? bail
[ "$CUR_SSID" = "$BEST_SSID" ] && exit 0

# Find network id for target SSID
nid="$(wpa_cli -i "$WIFI_IFACE" list_networks 2>/dev/null | awk -F'\t' -v s="$BEST_SSID" '$2==s{print $1; exit}')"
[ -z "$nid" ] && { notify "SSID $BEST_SSID not in wpa_supplicant"; exit 0; }

# Switch
wpa_cli -i "$WIFI_IFACE" select_network "$nid" >/dev/null 2>&1 || exit 0
notify "Switching Wi-Fi → ${BEST_SSID} (RSSI ${BEST_RSSI} dBm)"
SH
}

install_cron() {
  cat >"$CRON" <<CR
*/2 * * * * root $BIN >/dev/null 2>&1
CR
  chmod 0644 "$CRON"
  # reload cron so the new job is active
  service cron reload 2>/dev/null || service cron restart 2>/dev/null || true
}

ensure_deps
seed_conf
install_worker
install_cron
log "Installed cron job + worker for XBian (every 2 min)."
