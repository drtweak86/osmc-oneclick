#!/usr/bin/env bash
# --- Ensure unzip & latest rclone are present (safe to run repeatedly) ---
# Note: this phase runs as root under systemd, so apt-get is allowed.
if ! command -v unzip >/dev/null 2>&1; then
  apt-get update -y || true
  apt-get install -y unzip ca-certificates || true
fi

ensure_latest_rclone() {
  # Install/upgrade from official rclone script
  curl -fsSL https://rclone.org/install.sh | bash
}

if ! command -v rclone >/dev/null 2>&1; then
  echo "[oneclick][41_backup] rclone not found — installing…"
  ensure_latest_rclone
else
  # Optional: upgrade if older than a minimum you trust (e.g., 1.68)
  need_ver="1.68"
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p')"
  if [ -n "$have_ver" ]; then
    # If have_ver < need_ver, upgrade
    if [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; then
      echo "[oneclick][41_backup] rclone $have_ver < $need_ver — upgrading…"
      ensure_latest_rclone
    else
      echo "[oneclick][41_backup] rclone $have_ver OK (>= $need_ver)"
    fi
  else
    echo "[oneclick][41_backup] rclone version unknown — upgrading…"
    ensure_latest_rclone
  fi
fi
# --- end rclone ensure block ---

# Ensure new binaries are picked up and PATH is sane under systemd
hash -r
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

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
