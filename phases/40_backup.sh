#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="/var/log/osmc-oneclick"
LOG="${LOG_DIR}/backup.log"
BACKUP_DIR="/opt/osmc-oneclick/backups"
DATE="$(date +%F_%H-%M-%S)"
TARGET="${BACKUP_DIR}/osmc_backup_${DATE}.zip"
RCLONE_REMOTE="gdrive:osmc-backups"     # change if you used a different remote/folder

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

echo "[backup] ===== $(date) =====" >> "$LOG"

# sanity: rclone present?
if ! command -v rclone >/dev/null 2>&1; then
  echo "[backup] rclone not installed. Run: sudo apt-get update && sudo apt-get install -y rclone zip" >> "$LOG"
  exit 1
fi

# build archive (tweak include set to your liking)
zip -r "$TARGET" \
  /home/osmc/.kodi \
  /etc/wireguard \
  /opt/osmc-oneclick \
  >/dev/null

# upload
if rclone copy "$TARGET" "$RCLONE_REMOTE" >> "$LOG" 2>&1; then
  echo "[backup] upload ok: $(basename "$TARGET")" >> "$LOG"
else
  echo "[backup] upload FAILED" >> "$LOG"
  exit 1
fi

# verify upload exists remotely
if ! rclone ls "$RCLONE_REMOTE" | grep -q "$(basename "$TARGET")"; then
  echo "[backup] verify FAILED (not found in remote listing)" >> "$LOG"
  exit 1
fi

# rotation: keep last 3 (delete older)
# list newest first, skip first 3, delete the rest
rclone lsf --format "t" --dirs-only=false --files-only "$RCLONE_REMOTE" \
  | sort -r \
  | tail -n +4 \
  | while read -r old; do
      [ -n "$old" ] && rclone delete "${RCLONE_REMOTE}/${old}" >> "$LOG" 2>&1 || true
    done

# remove local once verified & rotated
rm -f "$TARGET"

echo "[backup] done" >> "$LOG"
