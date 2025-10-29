#!/usr/bin/env bash
set -euo pipefail

# Weekly self-care + backup skeleton
apt-get update
apt-get install -y --no-install-recommends cron rclone zip jq

# Create backup script
cat >/usr/local/sbin/osmc-backup.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

STAMP="$(date -u +%Y%m%d-%H%M%S)"
TMP="/tmp/osmc-backup-$STAMP"
OUT="/tmp/osmc-backup-$STAMP.zip"

mkdir -p "$TMP"
# minimal example: Kodi userdata + apt selections
tar -C /home/osmc -czf "$TMP/kodi_userdata.tgz" .kodi/userdata || true
dpkg --get-selections > "$TMP/apt-selections.txt" || true

(cd "$TMP" && zip -r "$OUT" . >/dev/null)

# rclone remote 'gdrive:' is assumed pre-configured by user
# Keep last 3
rclone copy "$OUT" gdrive:/osmc-backups/
rclone lsf --format pt --files-only gdrive:/osmc-backups/ \
  | sort -r | tail -n +4 | xargs -r -I{} rclone delete gdrive:/osmc-backups/"{}"

rm -rf "$TMP" "$OUT"
EOS
chmod +x /usr/local/sbin/osmc-backup.sh

# Cron: Sunday 00:00
( crontab -l 2>/dev/null; echo "0 0 * * 0 /usr/local/sbin/osmc-backup.sh >/var/log/osmc-backup.log 2>&1" ) | crontab -
systemctl enable --now cron || systemctl enable --now crond || true
