#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="/var/log/osmc-oneclick"
LOG="${LOG_DIR}/backup.log"
BACKUP_DIR="/opt/osmc-oneclick/backups"
DATE="$(date +%F_%H-%M-%S)"
TARGET="${BACKUP_DIR}/osmc_backup_${DATE}.zip"
RCLONE_REMOTE="gdrive:osmc-backups"   # adjust if your remote/folder differs

mkdir -p "$LOG_DIR" "$BACKUP_DIR"
echo "[backup] ===== $(date) =====" >> "$LOG"

# Sanity
command -v zip >/dev/null 2>&1    || { echo "[backup] zip missing" >> "$LOG"; exit 1; }
command -v rclone >/dev/null 2>&1 || { echo "[backup] rclone missing" >> "$LOG"; exit 1; }

# Build archive (adjust includes as you like)
zip -qr "$TARGET" \
  /home/osmc/.kodi \
  /etc/wireguard \
  /opt/osmc-oneclick \
  || { echo "[backup] zip failed" >> "$LOG"; exit 1; }

# Upload
if rclone copy "$TARGET" "$RCLONE_REMOTE" >> "$LOG" 2>&1; then
  echo "[backup] upload ok: $(basename "$TARGET")" >> "$LOG"
else
  echo "[backup] upload FAILED" >> "$LOG"
  exit 1
fi

# Verify uploaded file exists
if ! rclone lsf --files-only --format "p" "$RCLONE_REMOTE" | grep -qx "$(basename "$TARGET")"; then
  echo "[backup] verify FAILED (not found remotely)" >> "$LOG"
  exit 1
fi

# Rotate: keep newest 3 files in the remote, delete older ones
rclone lsf --files-only --format "p" "$RCLONE_REMOTE" \
  | sort -r \
  | tail -n +4 \
  | while IFS= read -r old; do
      [ -n "$old" ] && rclone delete "$RCLONE_REMOTE/$old" >> "$LOG" 2>&1 || true
    done

# Remove local copy after a successful verified upload
rm -f "$TARGET"
echo "[backup] done" >> "$LOG"
