#!/usr/bin/env bash
set -Eeuo pipefail

# --- Detect Kodi user/home (XBian uses 'xbian', OSMC uses 'osmc') ---
if id -u xbian >/dev/null 2>&1; then
  KODI_USER=xbian
elif id -u osmc >/dev/null 2>&1; then
  KODI_USER=osmc
else
  echo "[backup] No xbian/osmc user found" >&2
  exit 1
fi
KODI_HOME="/home/${KODI_USER}/.kodi"

# --- Paths & destinations ---
LOG_DIR="/var/log/osmc-oneclick"
LOG="${LOG_DIR}/backup.log"
BACKUP_DIR="/opt/osmc-oneclick/backups"
DATE="$(date +%F_%H-%M-%S)"
TARGET="${BACKUP_DIR}/kodi_backup_${DATE}.zip"

# Set your rclone remote:bucket/folder (override with env if you like)
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive:osmc-backups}"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"
echo "[backup] ===== $(date) (${KODI_USER}) =====" | tee -a "$LOG"

# --- Sanity: tools ---
for bin in zip rclone; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[backup] $bin missing" | tee -a "$LOG"
    exit 1
  fi
done

# --- Build archive (adjust includes as you like) ---
# NOTE: make sure these paths exist; missing ones are skipped safely.
INCLUDE_LIST=(
  "$KODI_HOME"
  "/etc/wireguard"
  "/opt/osmc-oneclick"
)

echo "[backup] creating: $TARGET" | tee -a "$LOG"
zip -qr "$TARGET" "${INCLUDE_LIST[@]}" 2>>"$LOG" || {
  echo "[backup] zip failed" | tee -a "$LOG"
  exit 1
}

# --- Upload to rclone remote ---
echo "[backup] uploading to ${RCLONE_REMOTE}" | tee -a "$LOG"
if rclone copy "$TARGET" "$RCLONE_REMOTE" >>"$LOG" 2>&1; then
  echo "[backup] upload ok: $(basename "$TARGET")" | tee -a "$LOG"
else
  echo "[backup] upload FAILED" | tee -a "$LOG"
  exit 1
fi

# --- Verify uploaded file exists remotely ---
if ! rclone lsf --files-only --format "p" "$RCLONE_REMOTE" | grep -qx "$(basename "$TARGET")"; then
  echo "[backup] verify FAILED (not found on remote)" | tee -a "$LOG"
  exit 1
fi

# --- Rotate: keep newest 3 on the remote ---
echo "[backup] rotating remote backups (keep 3 newest)" | tee -a "$LOG"
rclone lsf --files-only --format "p" "$RCLONE_REMOTE" \
  | sort -r \
  | tail -n +4 \
  | while IFS= read -r old; do
      [ -n "$old" ] && rclone delete "${RCLONE_REMOTE}/$old" >>"$LOG" 2>&1 || true
    done

# --- Remove local copy after verified upload ---
rm -f "$TARGET"
echo "[backup] done" | tee -a "$LOG"
