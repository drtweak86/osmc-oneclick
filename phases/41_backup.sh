#!/usr/bin/env bash
set -euo pipefail

# --- Config (change if you want) ---
RCLONE="${RCLONE:-/usr/bin/rclone}"
REMOTE="${REMOTE:-gdrive:osmc-backups}"
BACKUPS_DIR="${BACKUPS_DIR:-/home/osmc/backups}"
KODI_HOME="${KODI_HOME:-/home/osmc}"

# --- Helpers ---
log()    { echo "[oneclick][41_backup] $*" >&2; }
notify() {
  # Try kodi-send; if not present, just log
  if command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification($1,$2,8000)" || true
  else
    log "Notify: $1 - $2"
  fi
}

# --- Prep ---
mkdir -p "$BACKUPS_DIR"

STAMP="$(date +%F_%H%M)"
BACKUP_FILE="$BACKUPS_DIR/kodi_${STAMP}.zip"

cd "$KODI_HOME"

# --- Make backup (exclude fat caches) ---
log "Creating backup: $BACKUP_FILE"
notify "Backups" "Creating backup…"
zip -r9 "$BACKUP_FILE" .kodi \
  -x ".kodi/userdata/Thumbnails/*" \
  -x ".kodi/temp/*" \
  -x ".kodi/addons/packages/*" || true
chown osmc:osmc "$BACKUP_FILE" || true

# --- Upload ---
notify "Backups" "Uploading to Google Drive…"
log "Uploading to $REMOTE/$STAMP/"
"$RCLONE" copy "$BACKUP_FILE" "$REMOTE/$STAMP/" --fast-list

# --- Retention: keep newest 3 folders (no --sort flag used) ---
log "Applying retention (keep newest 3)"
# List directories as: "<ISO-TIME><TAB><NAME>", newest first, drop first 3, purge the rest
OLD_DIRS=$(
  "$RCLONE" lsf "$REMOTE" --dirs-only -F "tp" -s $'\t' \
  | sort -r \
  | awk -F $'\t' 'NR>3{print $2}'
)
if [ -n "${OLD_DIRS:-}" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    log "Purging $d"
    "$RCLONE" purge "$REMOTE/$d" || true
  done <<<"$OLD_DIRS"
fi

notify "Backups" "Done: $STAMP"
log "Backup finished"
exit 0
