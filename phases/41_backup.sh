#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/41_backup.sh
# Creates/updates systemd service+timer to run 40_backup.sh on a schedule.
set -euo pipefail

log(){ echo "[oneclick][41_backup] $*"; }

WORKER="/opt/xbian-oneclick/phases/40_backup.sh"
[ -x "$WORKER" ] || { log "ERROR: $WORKER not found/executable"; exit 1; }

# Service
cat >/etc/systemd/system/oneclick-backup.service <<UNIT
[Unit]
Description=OSMC OneClick: backup to cloud
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$WORKER
Nice=10
IOSchedulingClass=best-effort
UNIT

# Timer (daily at 03:10, with jitter)
cat >/etc/systemd/system/oneclick-backup.timer <<UNIT
[Unit]
Description=Run OneClick backup daily

[Timer]
OnCalendar=*-*-* 03:10:00
Persistent=true
RandomizedDelaySec=8m

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now oneclick-backup.timer

# Friendly Kodi toast if available
if command -v kodi-send >/dev/null 2>&1; then
  nofail kodi-send --action="Notification(Backups,Daily backup timer enabled,6000)" || true
fi

log "Installed/started oneclick-backup.timer (runs $WORKER)"
