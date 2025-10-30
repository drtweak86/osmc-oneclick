#!/usr/bin/env bash
# phases/33_wifi_autoswitch.sh
# Wi-Fi autoswitcher (media-streaming friendly): prefers PREFERRED_SSIDS, avoids flapping,
# warns if weak signal, switches only on meaningful improvement (≥5 dB by default).

set -euo pipefail
log(){ echo "[oneclick][33_wifi_autoswitch] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

# -------- Install default config (create only if missing) -------------------
CONF="/etc/default/wifi-autoswitch"
if [ ! -f "$CONF" ]; then
  log "Writing default /etc/default/wifi-autoswitch"
  install -d -m 0755 /etc/default
  cat >"$CONF"<<'CFG'
# /etc/default/wifi-autoswitch
# OneClick default profile: optimised for media streaming stability.

# Wi-Fi interface
WIFI_IFACE="wlan0"

# Streaming thresholds
STREAM_RSSI_DBM=-68     # warn if current link worse (more negative)
MIN_SIGNAL_PCT=55       # only used with ConnMan signal% if available

# Scan cadence
RUN_EVERY_SEC=120       # systemd timer period

# Notifications
KODI_NOTIFY=1

# Preferred SSIDs (order = priority)
PREFERRED_SSIDS=("Batcave" "🐢")

# Switching behaviour
AUTO_SWITCH=1           # 1 = switch to best preferred SSID when ≥5 dB better
SWITCH_DELTA_DB=5       # minimum improvement to trigger a switch

CFG
fi

# -------- Install autoswitch script ----------------------------------------
BIN="/usr/local/sbin/wifi-autoswitch"
install -d -m 0755 /usr/local/sbin
cat >"$BIN"<<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Load config
CONF="/etc/default/wifi-autoswitch"
[ -f "$CONF" ] && . "$CONF"

# Defaults if not set
WIFI_IFACE="${WIFI_IFACE:-wlan0}"
STREAM_RSSI_DBM="${STREAM_RSSI_DBM:- -68}"
RUN_EVERY_SEC="${RUN_EVERY_SEC:-120}"
KODI_NOTIFY="${KODI_NOTIFY:-1}"
AUTO_SWITCH="${AUTO_SWITCH:-1}"
SWITCH_DELTA_DB="${SWITCH_DELTA_DB:-5}"

# Simple Kodi toast
toast(){
  local heading="$1" msg="$2"
  if [ "$KODI_NOTIFY" = "1" ] && command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(${heading},${msg},6000)" >/dev/null 2>&1 || true
  fi
}

# Current SSID/RSSI
cur_ssid(){ iwgetid -r 2>/dev/null || true; }
cur_rssi(){
  local l
  l="$(iw dev "$WIFI_IFACE" link 2>/dev/null | awk '/signal:/ {print $2}')" || true
  echo "${l:-0}"
}

# ConnMan helpers (OSMC)
cm_has(){ command -v connmanctl >/dev/null 2>&1; }
cm_scan(){ connmanctl scan wifi >/dev/null 2>&1 || true; }
cm_services(){ connmanctl services 2>/dev/null || true; }
cm_connect(){
  # $1 = SSID -> resolve service then connect
  local ssid="$1" svc
  svc="$(cm_services | awk -v s="$ssid" '$0 ~ s {print $NF; exit}')" || true
  [ -n "$svc" ] && connmanctl connect "$svc" >/dev/null 2>&1
}

# NetworkManager / wpa_cli fallbacks
nm_connect(){ nmcli dev wifi connect "$1" >/dev/null 2>&1; }
wpa_connect(){
  # $1 = SSID
  local id
  id="$(wpa_cli -i "$WIFI_IFACE" list_networks 2>/dev/null | awk -v s="$1" '$0 ~ s {print $1; exit}')" || true
  [ -n "$id" ] || return 1
  wpa_cli -i "$WIFI_IFACE" select_network "$id" >/dev/null 2>&1 || return 1
  wpa_cli -i "$WIFI_IFACE" enable_network "$id" >/dev/null 2>&1 || true
  wpa_cli -i "$WIFI_IFACE" save_config >/dev/null 2>&1 || true
}

# Scan with iw (works everywhere)
scan_iw(){
  # prints: "<RSSI_DBM>\t<SSID>"
  iw dev "$WIFI_IFACE" scan 2>/dev/null \
    | awk '
      /^BSS / {sig=""; ssid=""}
      /signal:/ {sig=$2}
      /^\\tSSID:/ { sub("^\\tSSID: ", "", $0); ssid=$0; if (ssid != "") print int(sig), ssid }
    ' | sort -nr
}

# Choose best SSID (pref list first, then strongest)
choose_best(){
  # outputs "RSSI\tSSID"
  local preferred=("${PREFERRED_SSIDS[@]}")
  local lines="$(scan_iw)"

  # filter to preferred (in preference order), pick strongest among each name
  for p in "${preferred[@]}"; do
    # strongest instance of this SSID
    local row
    row="$(printf '%s\n' "$lines" | awk -v s="$p" '$0 ~ "\\t" s"$" {print $0}' | sort -nr | head -n1)"
    [ -n "$row" ] && echo "$row" && return 0
  done

  # fallback: strongest of anything we already know (visible in wpa_supplicant)
  if command -v wpa_cli >/dev/null 2>&1; then
    local known
    while read -r _ id ssid _; do
      [ -n "$ssid" ] || continue
      local row
      row="$(printf '%s\n' "$lines" | awk -v s="$ssid" '$0 ~ "\\t" s"$" {print $0}' | sort -nr | head -n1)"
      [ -n "$row" ] && echo "$row" && return 0
    done < <(wpa_cli -i "$WIFI_IFACE" list_networks 2>/dev/null | tail -n +3)
  fi

  # last resort: strongest from scan
  printf '%s\n' "$lines" | head -n1
}

main(){
  local curS curR bestR bestS delta

  curS="$(cur_ssid)"
  curR="$(cur_rssi)"     # e.g. -63

  # warn if weak for streaming
  if [ -n "$curR" ] && [ "$curR" -lt 0 ] && [ "$curR" -lt "$STREAM_RSSI_DBM" ]; then
    toast "Wi-Fi" "Weak signal on '${curS}' (${curR} dBm). Streaming may stutter."
  fi

  # scan + choose
  local bestLine
  bestLine="$(choose_best)"
  bestR="$(echo "$bestLine" | awk "{print \$1}")"
  bestS="$(echo "$bestLine" | cut -f2- )"

  # nothing to do?
  [ -z "$bestS" ] && exit 0

  # already on best?
  if [ "$bestS" = "$curS" ]; then
    exit 0
  fi

  # Only switch if improvement is meaningful
  if [ "$AUTO_SWITCH" = "1" ] && [ -n "$curR" ] && [ "$curR" -lt 0 ] && [ -n "$bestR" ]; then
    delta=$(( bestR - curR ))   # e.g. -55 - (-70) = 15 (dB better)
    if [ "$delta" -lt "$SWITCH_DELTA_DB" ]; then
      # not a big enough win; stay put
      exit 0
    fi
  else
    # not auto-switching; just warn
    exit 0
  fi

  # Try to connect (ConnMan -> NM -> wpa_cli)
  if cm_has; then
    cm_scan
    cm_connect "$bestS" || true
  elif command -v nmcli >/dev/null 2>&1; then
    nm_connect "$bestS" || true
  else
    wpa_connect "$bestS" || true
  fi

  sleep 2
  local newS="$(cur_ssid)"
  if [ "$newS" = "$bestS" ]; then
    toast "Wi-Fi" "Switched to '${bestS}' (${bestR} dBm)"
  fi
}

main "$@"
SH
chmod +x "$BIN"

# -------- systemd unit + timer ---------------------------------------------
install -d -m 0755 /etc/systemd/system

cat >/etc/systemd/system/wifi-autoswitch.service <<'UNIT'
[Unit]
Description=Wi-Fi autoswitch (streaming-friendly)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wifi-autoswitch
Nice=10
IOSchedulingClass=best-effort
UNIT

cat >/etc/systemd/system/wifi-autoswitch.timer <<'UNIT'
[Unit]
Description=Run Wi-Fi autoswitch periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Persistent=true
RandomizedDelaySec=15s

[Install]
WantedBy=timers.target
UNIT

# -------- Enable timer ------------------------------------------------------
systemctl daemon-reload
systemctl enable --now wifi-autoswitch.timer

log "Installed: /etc/default/wifi-autoswitch (create-once), /usr/local/sbin/wifi-autoswitch, systemd timer."
log "Edit SSIDs in /etc/default/wifi-autoswitch if needed; timer runs every 2 min."
