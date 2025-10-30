#!/usr/bin/env bash
set -euo pipefail

. /opt/osmc-oneclick/phases/31_helpers.sh

_log "[40_maintenance] Installing weekly maintenance service/timer"

# Write service
cat >/etc/systemd/system/osmc-weekly-maint.service <<'UNIT'
[Unit]
Description=OSMC weekly maintenance
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/osmc-oneclick/scripts/run-weekly-maint.sh
Nice=10
IOSchedulingClass=best-effort
UNIT

# Write timer (Sun 03:30)
cat >/etc/systemd/system/osmc-weekly-maint.timer <<'UNIT'
[Unit]
Description=Run OSMC weekly maintenance

[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true
RandomizedDelaySec=5m

[Install]
WantedBy=timers.target
UNIT

install -d -m 0755 /opt/osmc-oneclick/scripts

# Maintenance script
cat >/opt/osmc-oneclick/scripts/run-weekly-maint.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[weekly-maint] $*"; }

log "APT update/upgrade (noninteractive)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade -y || true
apt-get autoremove -y || true
apt-get clean -y || true

log "Prune Kodi temp & old thumbnails (>30d)"
find /home/osmc/.kodi/temp -type f -mtime +7 -delete 2>/dev/null || true
find /home/osmc/.kodi/userdata/Thumbnails -type f -mtime +30 -delete 2>/dev/null || true

log "SQLite VACUUM (textures & videos if present)"
for db in /home/osmc/.kodi/userdata/Database/Textures*.db /home/osmc/.kodi/userdata/Database/MyVideos*.db; do
  [ -f "$db" ] && sqlite3 "$db" 'PRAGMA journal_mode=WAL; VACUUM;'
done

log "Journal & filesystem housekeeping"
journalctl --vacuum-time=14d || true
fstrim -av || true

log "Unbound (if installed) sanity"
systemctl is-enabled --quiet unbound && systemctl restart unbound || true

log "Done."
SH

chmod +x /opt/osmc-oneclick/scripts/run-weekly-maint.sh

systemctl daemon-reload
systemctl enable --now osmc-weekly-maint.timer

kodi_dialog "Maintenance" "Weekly maintenance scheduled (Sundays 03:30)."
_log "[40_maintenance] Timer enabled."
