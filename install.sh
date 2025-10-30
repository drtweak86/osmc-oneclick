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
retry() {
  # retry <n> <sleep_seconds> <cmd...>
  local n=$1 s=$2; shift 2
  local i
  for i in $(seq 1 "$n"); do
    if "$@"; then return 0; fi
    warn "Retry $i/$n failed: $*"
    sleep "$s"
  done
  return 1
}

ensure_dirs() { for d in "$@"; do mkdir -p "$d"; done; }

normalize_sh() {
  sed -i 's/\r$//' "$1" 2>/dev/null || true
  sed -i '1s|^#!.*|#!/usr/bin/env bash|' "$1" 2>/dev/null || true
  chmod +x "$1" 2>/dev/null || true
}

stub_body() {
  cat <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "[oneclick][phase] $(basename "$0") (stub) — nothing to do" >&2
exit 0
SH
}

fetch_or_stub() {
  # fetch_or_stub <relative_path_under_repo>
  local rel="$1"
  local dst="$BASE_DIR/$rel"
  local url="$RAW_BASE/$rel"
  ensure_dirs "$(dirname "$dst")"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$dst"; then
      log "Fetched $rel from repo"
      normalize_sh "$dst"
      return 0
    fi
  fi
  warn "Could not fetch $rel — writing stub"
  stub_body >"$dst"
  normalize_sh "$dst"
}

ensure_phase_exec() {
  # ensure_phase_exec phases/XX_name.sh
  local rel="$1" p="$BASE_DIR/$1"
  if [ ! -f "$p" ]; then
    fetch_or_stub "$rel"
  else
    normalize_sh "$p"
  fi
}

# ------------------------- bootstrap FS & deps -------------------------------
ensure_dirs "$BASE_DIR" "$ASSETS" "$PHASES"
touch "$LOGFILE" || true
log "Starting OneClick installer (self-healing)…"

# unzip + CA certs (safe if already installed)
if ! command -v unzip >/dev/null 2>&1; then
  log "Installing unzip and CA certificates..."
  retry 2 5 apt-get update -y || true
  retry 2 5 apt-get install -y unzip ca-certificates || true
fi

# rclone (install/upgrade to >= 1.68)
if ! command -v rclone >/dev/null 2>&1; then
  log "rclone not found — installing…"
  retry 2 5 bash -c 'curl -fsSL https://rclone.org/install.sh | bash' || warn "rclone install script failed"
else
  need_ver="1.68"
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p')"
  if [ -n "${have_ver:-}" ] && [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; then
    log "rclone $have_ver < $need_ver — upgrading…"
    retry 2 5 bash -c 'curl -fsSL https://rclone.org/install.sh | bash' || warn "rclone upgrade failed"
  else
    log "rclone ${have_ver:-unknown} OK (>= $need_ver)"
  fi
fi

# Make sure mediacenter (Kodi) can be controlled later
if ! systemctl is-enabled mediacenter >/dev/null 2>&1; then
  log "Enabling mediacenter service…"
  systemctl enable mediacenter || true
fi

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
  ensure_phase_exec "$rel"
done

# shellcheck disable=SC1091
. "$PHASES/31_helpers.sh" 2>/dev/null || true

# Systemd daemon-reload in case new units arrived
systemctl daemon-reload || true

# ---------------- backup + maintenance timers (if phase present) -------------
if [ -x "$PHASES/41_backup.sh" ]; then
  log "Installing backup + maintenance timers…"
  systemctl enable --now oneclick-maint.timer  || warn "maint.timer enable failed"
  systemctl enable --now oneclick-backup.timer || warn "backup.timer enable failed"
else
  warn "41_backup.sh not executable — skipping timers."
fi

# ---------------- Pi performance tuning (20_optimize.sh) ---------------------
log "Running Raspberry Pi tuning (20_optimize.sh)…"
bash "$PHASES/20_optimize.sh" || warn "Pi tuning returned non-zero"

# ---------------- Argon One Pi4 V2 fan control setup ------------------------
log "Running Argon One setup (22_argon_one.sh)…"
bash "$PHASES/22_argon_one.sh" || warn "Argon setup returned non-zero"

# ---------------- Add-ons phase ---------------------------------------------
log "Running add-on installation phase (42_addons.sh)…"
bash "$PHASES/42_addons.sh" || warn "Add-ons phase returned non-zero"

# ---------------- Skin + fonts (Arctic Fuse 2 + EXO2) -----------------------
log "Applying skin (43_skin.sh)…"
bash "$PHASES/43_skin.sh" || warn "Skin phase returned non-zero"

log "Installing EXO2 fonts (43_fonts.sh)…"
bash "$PHASES/43_fonts.sh" || warn "Fonts phase returned non-zero"

# ---------------- Advanced settings (no cache overrides on Kodi 21) ----------
log "Applying advancedsettings + GUI presets (44_advanced.sh)…"
bash "$PHASES/44_advanced.sh" || warn "Advanced phase returned non-zero"

# ---------------- Finish up --------------------------------------------------
# Ownership nicety for Kodi profile files that phases may have touched
chown -R osmc:osmc /home/osmc/.kodi 2>/dev/null || true

log "OneClick install complete."
echo "[oneclick][install] You can reboot or restart Kodi with: sudo systemctl restart mediacenter" | tee -a "$LOGFILE"
exit 0
