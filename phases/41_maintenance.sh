#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="/var/log/osmc-oneclick"
LOG="${LOG_DIR}/maintenance.log"
mkdir -p "$LOG_DIR"

echo "[maintenance] ===== $(date) =====" >> "$LOG"

# System update/cleanup
sudo apt-get update -y >> "$LOG" 2>&1 || true
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$LOG" 2>&1 || true
sudo apt-get autoremove -y >> "$LOG" 2>&1 || true
sudo apt-get autoclean -y >> "$LOG" 2>&1 || true

# Kodi temp & thumbnails (older than X days)
find /home/osmc/.kodi/temp -type f -mtime +7 -print -delete >> "$LOG" 2>&1 || true
find /home/osmc/.kodi/userdata/Thumbnails -type f -mtime +30 -print -delete >> "$LOG" 2>&1 || true

# SQLite vacuum (video/music dbs)
shopt -s nullglob
for db in /home/osmc/.kodi/userdata/Database/MyVideos*.db /home/osmc/.kodi/userdata/Database/MyMusic*.db; do
  sqlite3 "$db" 'PRAGMA optimize; VACUUM;' >> "$LOG" 2>&1 || true
done

# Trim filesystems (helps SD wear/IO)
if command -v fstrim >/dev/null 2>&1; then
  sudo fstrim -v / >> "$LOG" 2>&1 || true
fi

echo "[maintenance] done" >> "$LOG"
