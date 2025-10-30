#!/usr/bin/env bash
# OneClick full installer for OSMC / Kodi 21 (Omega)
# Self-healing: creates dirs, normalizes phases, fetches missing scripts, or stubs them.

set -euo pipefail

BASE_DIR="/opt/osmc-oneclick"
ASSETS="$BASE_DIR/assets"
PHASES="$BASE_DIR/phases"
LOGFILE="/var/log/osmc-oneclick-install.log"
RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"

log()   { echo "[oneclick][install] $*" | tee -a "$LOGFILE"; }
warn()  { echo "[oneclick][WARN] $*" | tee -a "$LOGFILE" >&2; }
error() { echo "[oneclick][ERROR] $*" | tee -a "$LOGFILE" >&2; exit 1; }

trap 'rc=$?; [ $rc -ne 0 ] && echo "[oneclick][ERROR] install.sh failed (rc=$rc). See $LOGFILE" | tee -a "$LOGFILE"' EXIT

# ----------------------------- helpers --------------------------------------
retry() { local n=$1 s=$2; shift 2; for i in $(seq 1 "$n"); do "$@" && return 0 || true; warn "Retry $i/$n failed: $*"; sleep "$s"; done; return 1; }
ensure_dirs() { for d in "$@"; do mkdir -p "$d"; done; }
normalize_sh() { sed -i 's/\r$//' "$1" 2>/dev/null || true; sed -i '1s|^#!.*|#!/usr/bin/env bash|' "$1" 2>/dev/null || true; chmod +x "$1" 2>/dev/null || true; }
stub_body() {
  cat <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "[oneclick][phase] $(basename "$0") (stub) — nothing to do" >&2
exit 0
SH
}
fetch_or_stub() {
  local rel="$1"; local dst="$BASE_DIR/$rel"; local url="$RAW_BASE/$rel"
  ensure_dirs "$(dirname "$dst")"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$dst"; then
      log "Fetched $rel from repo"; normalize_sh "$dst"; return 0
    fi
  fi
  warn "Could not fetch $rel — writing stub"; stub_body >"$dst"; normalize_sh "$dst"
}
ensure_phase_exec() {
  local rel="$1" p="$BASE_DIR/$1"
  if [ ! -f "$p" ]; then fetch_or_stub "$rel"; else normalize_sh "$p"; fi
}

# ------------------------- bootstrap FS -------------------------------------
ensure_dirs "$BASE_DIR" "$ASSETS" "$PHASES"
touch "$LOGFILE" || true
log "Starting OneClick installer (self-healing)…"

# --------------------- ensure phases exist (fetch or stub) -------------------
for rel in \
  "phases/04_prereqs.sh" \
  "phases/05_pi_tune.sh" \
  "phases/20_optimize.sh" \
  "phases/22_argon_one.sh" \
  "phases/30_vpn.sh" \
  "phases/31_helpers.sh" \
  "phases/31_toast.sh" \
  "phases/31_vpn_autoswitch.sh" \
  "phases/32_enable_autoswitch.sh" \
  "phases/33_install_speedtest.sh" \
  "phases/33_wifi_autoswitch.sh" \
  "phases/40_backup.sh" \
  "phases/40_maintenance.sh" \
  "phases/41_backup.sh" \
  "phases/42_addons.sh" \
  "phases/43_fonts.sh" \
  "phases/44_advanced.sh" \
  "phases/45_kodi_qol.sh"
do
  ensure_phase_exec "$rel"
done

# shellcheck disable=SC1091
. "$PHASES/31_helpers.sh" 2>/dev/null || true

# Make sure mediacenter (Kodi) can be controlled later
if ! systemctl is-enabled mediacenter >/dev/null 2>&1; then
  log "Enabling mediacenter service…"
  systemctl enable mediacenter || true
fi

# Systemd daemon-reload in case new units arrived
systemctl daemon-reload || true

# -------------------- Run phases in correct order ---------------------------
log "Running prerequisites (04_prereqs.sh)…"
bash "$PHASES/04_prereqs.sh" || warn "Prereqs returned non-zero"

log "Applying Pi tuning (05_pi_tune.sh)…"
bash "$PHASES/05_pi_tune.sh" || warn "Pi tuning returned non-zero"

log "Applying system optimisations (20_optimize.sh)…"
bash "$PHASES/20_optimize.sh" || warn "Optimize returned non-zero"

log "Setting up Argon One (22_argon_one.sh)…"
bash "$PHASES/22_argon_one.sh" || warn "Argon setup returned non-zero"

log "Installing VPN bits (30_vpn.sh)…"
bash "$PHASES/30_vpn.sh" || warn "VPN phase returned non-zero"

log "Installing speedtest (33_install_speedtest.sh)…"
bash "$PHASES/33_install_speedtest.sh" || warn "Speedtest phase returned non-zero"

log "Installing Wi-Fi autoswitch (33_wifi_autoswitch.sh)…"
bash "$PHASES/33_wifi_autoswitch.sh" || warn "Wi-Fi autoswitch returned non-zero"

log "Configuring maintenance (40_maintenance.sh)…"
bash "$PHASES/40_maintenance.sh" || warn "Maintenance phase returned non-zero"

# 41_backup.sh is an on-demand backup helper (kept; no timer created here)
log "Preparing backup helper (41_backup.sh)…"
bash "$PHASES/41_backup.sh" || warn "Backup helper returned non-zero"

log "Installing add-ons and switching skin (42_addons.sh)…"
bash "$PHASES/42_addons.sh" || warn "Add-ons phase returned non-zero"

log "Installing EXO2 fonts (43_fonts.sh)…"
bash "$PHASES/43_fonts.sh" || warn "Fonts phase returned non-zero"

log "Installing advancedsettings.xml (44_advanced.sh)…"
bash "$PHASES/44_advanced.sh" || warn "Advanced phase returned non-zero"

log "Applying Kodi QoL (45_kodi_qol.sh)…"
bash "$PHASES/45_kodi_qol.sh" || warn "QoL phase returned non-zero"

# ---------------- timers: enable if present ----------------------------------
enable_if_present() {
  local unit="$1"
  if systemctl list-unit-files | grep -q "^${unit}"; then
    log "Enabling ${unit}"
    systemctl enable --now "$unit" || true
  fi
}
# Maintenance timer name from 40_maintenance.sh
enable_if_present "osmc-weekly-maint.timer"
# Wi-Fi autoswitch (from 33_wifi_autoswitch.sh)
enable_if_present "wifi-autoswitch.timer"
# VPN autoswitch (from 32_enable_autoswitch.sh)
enable_if_present "wg-autoswitch.timer"

# ---------------- Finish up --------------------------------------------------
# Ownership nicety for Kodi profile files that phases may have touched
chown -R osmc:osmc /home/osmc/.kodi 2>/dev/null || true

log "OneClick install complete."
echo "[oneclick][install] You can reboot or restart Kodi with: sudo systemctl restart mediacenter" | tee -a "$LOGFILE"
exit 0
