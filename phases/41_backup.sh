#!/usr/bin/env bash
# phases/41_backup.sh — XBian/OSMC compatible backup scheduler
set -euo pipefail
log(){ echo "[oneclick][41_backup] $*"; }

WORKER="/opt/osmc-oneclick/phases/40_backup.sh"
[ -x "$WORKER" ] || { log "ERROR: $WORKER not found or not executable"; exit 1; }

log "Installing daily backup cron job for XBian/OSMC"

# --- Detect Kodi user for optional toast ---
if id -u xbian >/dev/null 2>&1; then
  KODI_USER=xbian
elif id -u osmc >/dev/null 2>&1; then
  KODI_USER=osmc
else
  KODI_USER=""
fi

# --- Ensure log directory ---
install -d -m 0755 /var/log/osmc-oneclick

# --- Cron job (runs daily 03:10, output logged) ---
cat >/etc/cron.d/oneclick-backup <<'CRON'
# Run OneClick backup daily at 03:10
10 3 * * * root /opt/osmc-oneclick/phases/40_backup.sh >/var/log/osmc-oneclick/daily-backup.log 2>&1
CRON
chmod 0644 /etc/cron.d/oneclick-backup

# --- Reload/restart cron to apply ---
service cron reload >/dev/null 2>&1 || service cron restart >/dev/null 2>&1

# --- Friendly toast if Kodi is available ---
if command -v kodi-send >/dev/null 2>&1; then
  kodi-send --action="Notification(Backups,Daily backup scheduled,6000)" >/dev/null 2>&1 || true
elif [ -n "$KODI_USER" ]; then
  sudo -u "$KODI_USER" bash -c 'command -v kodi-send >/dev/null 2>&1 && kodi-send --action="Notification(Backups,Daily backup scheduled,6000)"' || true
fi

log "Daily backup scheduled (03:10). Log: /var/log/osmc-oneclick/daily-backup.log"
