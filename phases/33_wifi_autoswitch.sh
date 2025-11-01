#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/33_wifi_autoswitch.sh
# Wi-Fi autoswitch for OSMC (ConnMan): prefer strongest of preferred SSIDs,
# with streaming-friendly thresholds + optional Kodi notifications.
#
# Seeds /etc/default/wifi-autoswitch from assets/config if present.
# Installs:
#   - /usr/local/sbin/wifi-autoswitch (worker)
#   - systemd service + timer (runs every 2 minutes)

set -euo pipefail
log(){ echo "[oneclick][33_wifi_autoswitch] $*"; }
warn(){ echo "[oneclick][WARN] $*">&2; }

ASSETS_BASE="${ASSETS_BASE:-/opt/xbian-oneclick/assets}"
ASSET_CFG="${ASSETS_BASE}/config/wifi-autoswitch"
CONF="/etc/default/wifi-autoswitch"
BIN="/usr/local/sbin/wifi-autoswitch"
SVC="/etc/systemd/system/wifi-autoswitch.service"
TMR="/etc/systemd/system/wifi-autoswitch.timer"

ensure_dep() {
  command -v connmanctl >/dev/null 2>&1 || {
    warn "connmanctl not found. OSMC/ConnMan is required for Wi-Fi autoswitch."
    exit 0
  }
  command -v bash >/dev/null 2>&1 || true
  command -v sed >/dev/null 2>&1 || true
  command -v awk >/dev/null 2>&1 || true
}

seed_default_conf() {
  # 1) Prefer repo asset if present and no local file yet
  if [[ ! -f "$CONF" && -f "$ASSET_CFG" ]]; then
    log "Seeding ${CONF} from assets/config/wifi-autoswitch"
    install -o root -g root -m 0644 "$ASSET_CFG" "$CONF"
    return
  fi

  # 2) Otherwise, write a sensible default once
  if [[ ! -f "$CONF" ]]; then
    log "Creating default ${CONF} (streaming-friendly)"
    cat >"$CONF"<<'CFG'
# /etc/default/wifi-autoswitch
# Default configuration for OneClick Wi-Fi autoswitcher (OSMC/ConnMan)
# Optimised for media streaming performance.

# --- Interface ---
WIFI_IFACE="wlan0"

# --- Streaming thresholds ---
# ConnMan reports Strength 0..100; warn/switch if below this
MIN_SIGNAL_PCT=55          # minimum acceptable strength
WARN_SIGNAL_PCT=60         # show a warning toast if falls below

# --- Timer cadence ---
RUN_EVERY_SEC=120          # controlled by systemd timer, documented here

# --- Notifications ---
KODI_NOTIFY=1              # 1=enable Kodi toasts (requires kodi-send in PATH)

# --- Preferred SSIDs (priority order) ---
# Put your favourites first; autoswitch prefers strongest among these.
# Unicode SSIDs are fine when quoted.
PREFERRED_SSIDS=("Batcave" "🐢")

# --- Switching logic ---
AUTO_SWITCH=1              # 1 = enable switching
SWITCH_DELTA_DB=5          # minimum “better by” (in ConnMan Strength points)
CFG
    chmod 0644 "$CONF"
  fi
}

install_worker() {
  log "Installing worker: ${BIN}"
  cat >"$BIN"<<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Load defaults
CONF="/etc/default/wifi-autoswitch"
[ -f "$CONF" ] && . "$CONF"

WIFI_IFACE="${WIFI_IFACE:-wlan0}"
MIN_SIGNAL_PCT="${MIN_SIGNAL_PCT:-55}"
WARN_SIGNAL_PCT="${WARN_SIGNAL_PCT:-60}"
RUN_EVERY_SEC="${RUN_EVERY_SEC:-120}"
KODI_NOTIFY="${KODI_NOTIFY:-1}"
AUTO_SWITCH="${AUTO_SWITCH:-1}"
SWITCH_DELTA_DB="${SWITCH_DELTA_DB:-5}"
# shellcheck disable=SC2207
PREFERRED_SSIDS=(${PREFERRED_SSIDS:-"Batcave" "🐢"})

say(){ echo "[wifi-autoswitch] $*"; }

toast() {
  local title="$1" msg="$2" icon=""
  command -v kodi-send >/dev/null 2>&1 || return 0
  [ "${KODI_NOTIFY}" = "1" ] || return 0
  nofail kodi-send --action="Notification(${title},${msg},6000,${icon})" >/dev/null 2>&1 || true
}

# Parse current service id for Wi-Fi
current_service_id() {
  # service id looks like: wifi_XXXX_managed_psk or *_open
  connmanctl services | awk '/^\*|^ /{print $NF" "$0}' | awk '/^wifi_/{print $1; exit}'
}

current_strength_and_ssid() {
  local sid="$1"
  # Query full properties for the service id
  connmanctl services "$sid" 2>/dev/null | awk '
    /^ *Strength/ { s=$NF }
    /^ *Name/     { sub(/^ *Name *= */, "", $0); name=$0 }
    END { if (s=="") s=0; print s"|"name }
  '
}

# Build list of all visible wifi services with details
scan_services() {
  connmanctl services 2>/dev/null | awk '/^ *wifi_/{print $NF}'
}

# Is this SSID in our preferred list?
is_preferred() {
  local ssid="$1"
  for p in "${PREFERRED_SSIDS[@]}"; do
    [[ "$ssid" == "$p" ]] && return 0
  done
  return 1
}

# Switch to a given service id (assumes credentials already known/saved)
switch_to() {
  local sid="$1" ssid="$2" strength="$3"
  say "Switching to ${ssid} (${strength}%) via ${sid}"
  toast "Wi-Fi" "Switching to ${ssid} (${strength}%)"
  connmanctl connect "$sid" >/dev/null 2>&1 || {
    say "connmanctl connect failed for $sid"
    return 1
  }
  return 0
}

main() {
  # Get currently connected Wi-Fi service (if any)
  local cur_id cur_info cur_strength cur_ssid
  cur_id="$(current_service_id || true)"

  if [ -n "$cur_id" ]; then
    cur_info="$(current_strength_and_ssid "$cur_id")"
    cur_strength="${cur_info%%|*}"
    cur_ssid="${cur_info#*|}"
    [[ -z "$cur_strength" ]] && cur_strength=0
    say "Current: ${cur_ssid:-unknown} (${cur_strength}%)"
    if (( cur_strength < WARN_SIGNAL_PCT )); then
      toast "Wi-Fi" "Weak signal on ${cur_ssid:-?}: ${cur_strength}%"
    fi
  else
    cur_strength=0
    cur_ssid=""
    say "Not currently connected via ConnMan Wi-Fi"
  fi

  # Scan visible Wi-Fi services and pick best preferred SSID by Strength
  local best_id="" best_ssid="" best_strength=-1
  while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    info="$(current_strength_and_ssid "$sid")"
    s="${info%%|*}"
    n="${info#*|}"
    [ -z "$s" ] && s=0

    # Consider only preferred SSIDs
    if is_preferred "$n"; then
      if (( s > best_strength )); then
        best_strength="$s"
        best_ssid="$n"
        best_id="$sid"
      fi
    fi
  done < <(scan_services)

  if [ -z "$best_id" ]; then
    say "No preferred SSIDs visible; doing nothing."
    exit 0
  fi

  say "Best preferred visible: ${best_ssid} (${best_strength}%)"

  # Decide whether to switch
  if [ -n "$cur_ssid" ] && [ "$cur_ssid" = "$best_ssid" ]; then
    # Already on the best preferred SSID
    say "Already on ${cur_ssid}; nothing to do."
    exit 0
  fi

  # If we’re on a different SSID:
  if (( AUTO_SWITCH )); then
    # Switch if improvement exceeds threshold OR current is below minimum
    if (( best_strength + 0 >= cur_strength + SWITCH_DELTA_DB )) || (( cur_strength < MIN_SIGNAL_PCT )); then
      switch_to "$best_id" "$best_ssid" "$best_strength" || exit 0
    else
      say "Staying on ${cur_ssid} (Δ=${best_strength-cur_strength} < ${SWITCH_DELTA_DB})"
    fi
  fi
}

main "$@"
SH
  chmod 0755 "$BIN"
}

install_units() {
  log "Writing systemd units"
  cat >"$SVC"<<UNIT
[Unit]
Description=Wi-Fi autoswitch (ConnMan) for streaming
After=network-online.target connman.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$BIN
Nice=10

[Install]
WantedBy=multi-user.target
UNIT

  cat >"$TMR"<<UNIT
[Unit]
Description=Run Wi-Fi autoswitch periodically

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min
Unit=wifi-autoswitch.service
Persistent=true
RandomizedDelaySec=15s

[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now wifi-autoswitch.timer
}

# ----- run -----
ensure_dep
seed_default_conf
install_worker
install_units
log "Wi-Fi autoswitch installed and timer enabled (every 2 min)."
