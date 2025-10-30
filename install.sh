#!/usr/bin/env bash
# OneClick full installer for OSMC / Kodi 21 (Omega)
# Handles dependency setup, Google Drive backup phase, add-ons, skin, and advanced settings.

set -euo pipefail

BASE_DIR="/opt/osmc-oneclick"
ASSETS="$BASE_DIR/assets"
PHASES="$BASE_DIR/phases"
LOGFILE="/var/log/osmc-oneclick-install.log"

log()   { echo "[oneclick][install] $*" | tee -a "$LOGFILE"; }
warn()  { echo "[oneclick][WARN] $*" | tee -a "$LOGFILE" >&2; }
error() { echo "[oneclick][ERROR] $*" | tee -a "$LOGFILE" >&2; exit 1; }

log "Starting OneClick installer..."

# --- Ensure unzip & latest rclone are present ---
if ! command -v unzip >/dev/null 2>&1; then
  log "Installing unzip and CA certificates..."
  apt-get update -y || true
  apt-get install -y unzip ca-certificates || true
fi

ensure_latest_rclone() {
  curl -fsSL https://rclone.org/install.sh | bash
}

if ! command -v rclone >/dev/null 2>&1; then
  log "rclone not found — installing..."
  ensure_latest_rclone
else
  need_ver="1.68"
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p')"
  if [ -n "$have_ver" ]; then
    if [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; then
      log "rclone $have_ver < $need_ver — upgrading..."
      ensure_latest_rclone
    else
      log "rclone $have_ver OK (>= $need_ver)"
    fi
  else
    log "rclone version unknown — upgrading..."
    ensure_latest_rclone
  fi
fi

# --- Run backup + maintenance setup ---
if [ -x "$PHASES/41_backup.sh" ]; then
  log "Installing backup + maintenance timers..."
  systemctl enable --now oneclick-maint.timer || true
  systemctl enable --now oneclick-backup.timer || true
else
  warn "41_backup.sh not found or not executable — skipping timers."
fi

# --- Add-ons phase ---
if [ -x "$PHASES/42_addons.sh" ]; then
  log "Running add-on installation phase..."
  bash "$PHASES/42_addons.sh"
else
  warn "42_addons.sh missing — skipping add-ons."
fi

# --- Apply Arctic Fuse 2 skin and fonts ---
log "Installing Arctic Fuse 2 skin and fonts..."
sudo -u osmc mkdir -p /home/osmc/.kodi/addons/skin.arctic.fuse.2/fonts
sudo cp -r "$ASSETS/skin.arctic.fuse.2" /home/osmc/.kodi/addons/
sudo cp "$ASSETS/fonts/"*.ttf /home/osmc/.kodi/addons/skin.arctic.fuse.2/fonts/
sudo cp "$ASSETS/skin.arctic.fuse.2/1080i/Font.xml" /home/osmc/.kodi/addons/skin.arctic.fuse.2/1080i/
sudo chown -R osmc:osmc /home/osmc/.kodi/addons/skin.arctic.fuse.2

# --- Apply advancedsettings.xml ---
if [ -f "$ASSETS/config/advancedsettings.xml" ]; then
  log "Installing advancedsettings.xml"
  sudo -u osmc mkdir -p /home/osmc/.kodi/userdata
  sudo cp "$ASSETS/config/advancedsettings.xml" /home/osmc/.kodi/userdata/advancedsettings.xml
  sudo chown osmc:osmc /home/osmc/.kodi/userdata/advancedsettings.xml
else
  warn "advancedsettings.xml not found in assets/config — skipping."
fi

# --- Final cleanup & confirmation ---
log "Installation complete!"
sudo -u osmc /usr/bin/kodi-send -a "Notification(Setup Complete,OneClick Installer finished successfully,8000)" || true
exit 0
