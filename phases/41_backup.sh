#!/usr/bin/env bash
set -euo pipefail

. /opt/osmc-oneclick/phases/31_helpers.sh

BACKUP_DIR="/opt/osmc-oneclick/backups"
SCRIPTS_DIR="/opt/osmc-oneclick/scripts"
REMOTE_NAME="gdrive"
REMOTE_PATH="gdrive:OSMC-Backups/$(hostname)"
KEEP=3

install -d -m 0755 "$SCRIPTS_DIR" "$BACKUP_DIR"

# --------- Google Drive auth helper ----------
ensure_gdrive() {
  if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:"; then
    return 0
  fi

  # If user dropped a token file, import it
  if [ -f /opt/osmc-oneclick/gdrive_token.json ]; then
    token=$(cat /opt/osmc-oneclick/gdrive_token.json)
    rclone config create "$REMOTE_NAME" drive scope=drive.file token="$token" config_is_local=false
    kodi_dialog "Google Drive" "Imported OAuth token and created remote '$REMOTE_NAME'."
    return 0
  fi

  # First-run guidance (popup + log)
  msg1="Google Drive setup: On a PC/Mobile, run: rclone authorize 'drive'"
  msg2="Copy the JSON output into /opt/osmc-oneclick/gdrive_token.json then rerun this phase."
  kodi_dialog "Authorize Google Drive" "$msg1"
  kodi_dialog "Authorize Google Drive" "$msg2"
  _log "[41_backup] $msg1"
  _log "[41_backup] $msg2"
  exit 2
}

# --------- backup runner ----------
cat >"$SCRIPTS_DIR/run-weekly-backup.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[weekly-backup] $*"; }
REMOTE_NAME="gdrive"
REMOTE_PATH="gdrive:OSMC-Backups/$(hostname)"
STAMP="$(date +%Y-%m-%d_%H-%M)"
TMP="/opt/osmc-oneclick/backups"
FILE="${TMP}/kodi-${STAMP}.tar.gz"

install -d -m 0755 "$TMP"

log "Packaging Kodi data"
tar --exclude='*.log' -czf "$FILE" \
  -C /home/osmc \
  .kodi/addons \
  .kodi/userdata \
  .kodi/system 2>/dev/null || true

log "Uploading to Google Drive"
rclone copy "$FILE" "$REMOTE_PATH" --progress

log "Verify upload"
rclone ls "$REMOTE_PATH" | grep "$(basename "$FILE")" >/dev/null

log "Keep last 3, purge older"
# list by modtime, skip last 3, delete the rest
rclone lsf --files-only --format "tp" --recursive "$REMOTE_PATH" \
  | sort -r \
  | awk 'NR>3{print $2}' \
  | while read -r old; do
      rclone deletefile "$REMOTE_PATH/$old" || true
    done

log "Remove local backup after verify"
rm -f "$FILE" || true

log "Done."
SH
chmod +x "$SCRIPTS_DIR/run-weekly-backup.sh"

# --------- systemd service + timer ----------
cat >/etc/systemd/system/osmc-weekly-backup.service <<'UNIT'
[Unit]
Description=OSMC weekly Google Drive backup
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/osmc-oneclick/scripts/run-weekly-backup.sh
Nice=10
IOSchedulingClass=best-effort
UNIT

cat >/etc/systemd/system/osmc-weekly-backup.timer <<'UNIT'
[Unit]
Description=Run OSMC weekly backup

[Timer]
OnCalendar=Sun *-*-* 03:45:00
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
UNIT

# --------- flow ----------
if ! command -v rclone >/dev/null 2>&1; then
  _log "[41_backup] rclone not found; install phase 10 must run first."
  exit 1
fi

ensure_gdrive

systemctl daemon-reload
systemctl enable --now osmc-weekly-backup.timer

kodi_dialog "Backups" "Weekly Google Drive backup scheduled (Sundays 03:45)."
_log "[41_backup] Timer enabled."
