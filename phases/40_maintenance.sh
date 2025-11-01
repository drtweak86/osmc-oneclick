#!/usr/bin/env bash
# phases/40_maintenance.sh — Weekly maintenance for XBian/OSMC (cron-based)
set -euo pipefail

log(){ echo "[oneclick][40_maintenance] $*"; }

log "Installing weekly maintenance cron job for XBian"

# --- Detect Kodi user/home ---
if id -u xbian >/dev/null 2>&1; then
  KODI_USER=xbian
elif id -u osmc >/dev/null 2>&1; then
  KODI_USER=osmc
else
  log "No xbian/osmc user found, aborting."
  exit 0
fi
KODI_HOME="/home/${KODI_USER}/.kodi"

# --- Ensure directories ---
install -d -m 0755 /opt/osmc-oneclick/scripts
install -d -m 0755 /var/log/osmc-oneclick

# --- Maintenance payload ---
cat >/opt/osmc-oneclick/scripts/run-weekly-maint.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if id -u xbian >/dev/null 2>&1; then
  KODI_USER=xbian
elif id -u osmc >/dev/null 2>&1; then
  KODI_USER=osmc
else
  echo "[weekly-maint] No xbian/osmc user found" >&2
  exit 0
fi
KODI_HOME="/home/${KODI_USER}/.kodi"

log(){ echo "[weekly-maint] $*"; }

log "APT update/upgrade (noninteractive)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y || true
apt-get autoremove -y || true
apt-get clean -y || true

log "Prune Kodi temp & old thumbnails"
find "$KODI_HOME/temp" -type f -mtime +7 -delete 2>/dev/null || true
find "$KODI_HOME/userdata/Thumbnails" -type f -mtime +30 -delete 2>/dev/null || true

log "SQLite VACUUM (textures/videos/music if present)"
for db in "$KODI_HOME/userdata/Database"/Textures*.db \
          "$KODI_HOME/userdata/Database"/MyVideos*.db \
          "$KODI_HOME/userdata/Database"/MyMusic*.db; do
  [ -f "$db" ] && command -v sqlite3 >/dev/null 2>&1 && sqlite3 "$db" 'PRAGMA journal_mode=WAL; VACUUM;' || true
done

log "Journal & FS housekeeping"
command -v journalctl >/dev/null 2>&1 && journalctl --vacuum-time=14d || true
command -v fstrim >/dev/null 2>&1 && fstrim -av || true

log "Unbound sanity (if enabled)"
if service unbound status >/dev/null 2>&1; then
  service unbound restart || true
fi

log "Done."
SH
chmod +x /opt/osmc-oneclick/scripts/run-weekly-maint.sh

# --- Cron job (Sunday 03:30) ---
cat >/etc/cron.d/osmc-weekly-maint <<'CRON'
# Run weekly maintenance (Sundays 03:30)
30 3 * * 0 root /opt/osmc-oneclick/scripts/run-weekly-maint.sh >/var/log/osmc-oneclick/weekly-maint.log 2>&1
CRON
chmod 0644 /etc/cron.d/osmc-weekly-maint

service cron reload >/dev/null 2>&1 || service cron restart >/dev/null 2>&1

log "Weekly maintenance scheduled (Sundays 03:30)."
