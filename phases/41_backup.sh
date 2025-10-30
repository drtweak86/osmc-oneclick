#!/usr/bin/env bash
set -Eeuo pipefail

# --- oneclick helpers ---
log() { echo "[oneclick][41_backup] $*"; }
notify() {
  local title="${1:-Backups}" msg="${2:-Working…}" ms="${3:-8000}"
  kodi-send --action="Notification(${title},${msg},${ms})" >/dev/null 2>&1 || true
}

# --- rclone + remote defaults ---
RCLONE_BIN="${RCLONE_BIN:-/usr/bin/rclone}"
RCLONE_CFG="${RCLONE_CFG:-/home/osmc/.config/rclone/rclone.conf}"
RCLONE="${RCLONE:-$RCLONE_BIN --config $RCLONE_CFG}"
REMOTE="${REMOTE:-gdrive:osmc-backups}"

# --- where to write the zip ---
BACKUP_DIR="/home/osmc/backups"
STAMP="$(date +%F_%H%M)"
BACKUP_FILE="${BACKUP_DIR}/kodi_${STAMP}.zip"

mkdir -p "$BACKUP_DIR"
cd /home/osmc

log "Creating backup: $BACKUP_FILE"
zip -r9 "$BACKUP_FILE" .kodi \
  -x ".kodi/userdata/Thumbnails/*" \
  -x ".kodi/temp/*" \
  -x ".kodi/addons/packages/*" || true
chown osmc:osmc "$BACKUP_FILE" || true

# Upload
notify "Backups" "Uploading to Google Drive…"
log "Uploading to $REMOTE/$STAMP/"
$RCLONE copy "$BACKUP_FILE" "$REMOTE/$STAMP/" --fast-list

# Retention: keep newest 3 folders (portable; no --sort)
log "Applying retention (keep newest 3)"
OLD_DIRS="$(
  $RCLONE lsf --dirs-only -F "t p" -s $'\t' "$REMOTE" \
  | sort -r \
  | awk -F $'\t' 'NR>3{print $2}'
)"
if [ -n "${OLD_DIRS:-}" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    log "Purging $d"
    $RCLONE purge "$REMOTE/$d" || true
  done <<<"$OLD_DIRS"
fi

log "Backup finished"
