#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/40_maintenance.sh
set -euo pipefail

# Helpers (kodi_dialog, log wrappers, etc.)
. /opt/xbian-oneclick/phases/31_helpers.sh || true

_log "[40_maintenance] Installing weekly maintenance service/timer"

install -d -m 0755 /opt/xbian-oneclick/scripts

# ---- Maintenance payload ---------------------------------------------------
cat >/opt/xbian-oneclick/scripts/run-weekly-maint.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[weekly-maint] $*"; }

log "APT update/upgrade (noninteractive)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y || true
apt-get autoremove -y || true
apt-get clean -y || true

log "Prune Kodi temp & old thumbnails"
find /home/xbian/.kodi/temp -type f -mtime +7 -delete 2>/dev/null || true
find /home/xbian/.kodi/userdata/Thumbnails -type f -mtime +30 -delete 2>/dev/null || true

log "SQLite VACUUM (textures/videos/music if present)"
for db in /home/xbian/.kodi/userdata/Database/Textures*.db \
          /home/xbian/.kodi/userdata/Database/MyVideos*.db \
          /home/xbian/.kodi/userdata/Database/MyMusic*.db; do
  [ -f "$db" ] && sqlite3 "$db" 'PRAGMA journal_mode=WAL; VACUUM;' || true
done

log "Journal & FS housekeeping"
journalctl --vacuum-time=14d || true
command -v fstrim >/dev/null 2>&1 && fstrim -av || true

log "Unbound sanity (if enabled)"
systemctl is-enabled --quiet unbound && systemctl restart unbound || true

log "Done."
SH
chmod +x /opt/xbian-oneclick/scripts/run-weekly-maint.sh

# ---- systemd unit + timer --------------------------------------------------
cat >/etc/systemd/system/xbian-weekly-maint.service <<'UNIT'
[Unit]
Description=OSMC weekly maintenance
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/xbian-oneclick/scripts/run-weekly-maint.sh
Nice=10
IOSchedulingClass=best-effort
UNIT

# Timer: Sunday 03:30 Europe/London
cat >/etc/systemd/system/xbian-weekly-maint.timer <<'UNIT'
[Unit]
Description=Run OSMC weekly maintenance

[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true
RandomizedDelaySec=5m
Unit=xbian-weekly-maint.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now xbian-weekly-maint.timer

# Friendly toast if Kodi is running
kodi_dialog "Maintenance" "Weekly maintenance scheduled (Sundays 03:30)."

_log "[40_maintenance] Timer enabled."
