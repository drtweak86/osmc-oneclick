#!/usr/bin/env bash
# phases/32_enable_autoswitch.sh — systemd if present, cron otherwise (XBian-safe)
set -euo pipefail

log(){ echo "[oneclick][32_enable_autoswitch] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

BASE="/opt/osmc-oneclick"
PHASES="$BASE/phases"
RUNNER_SRC="$PHASES/31_vpn_autoswitch.sh"
RUNNER_DST="/usr/local/sbin/wg-autoswitch"
DEFAULTS="/etc/default/wg-autoswitch"

# 1) Install runner
if [ -f "$RUNNER_SRC" ]; then
  install -m 0755 "$RUNNER_SRC" "$RUNNER_DST"
  log "Installed runner -> $RUNNER_DST"
else
  warn "Missing $RUNNER_SRC"
fi

# 2) Seed defaults if missing
if [ ! -f "$DEFAULTS" ]; then
  tee "$DEFAULTS" >/dev/null <<'EOF'
MIN_DL_MBIT=12
MAX_RTT_MS=80
MAX_LOSS_PCT=2
PING_TARGET=1.1.1.1
TEST_BYTES=$((4*1024*1024))
LOG_FILE=/var/log/wg-autoswitch.log
EOF
  log "Wrote $DEFAULTS"
fi

# 3) Prefer systemd if available; fallback to cron (XBian)
if command -v systemctl >/dev/null 2>&1; then
  SVC=/etc/systemd/system/wg-autoswitch.service
  TMR=/etc/systemd/system/wg-autoswitch.timer
  SRC_DIR="$BASE/systemd"

  # Install units if you’ve got them in repo
  if [ -f "$SRC_DIR/wg-autoswitch.service" ]; then
    cp -f "$SRC_DIR/wg-autoswitch.service" "$SVC"
  fi
  if [ -f "$SRC_DIR/wg-autoswitch.timer" ]; then
    cp -f "$SRC_DIR/wg-autoswitch.timer" "$TMR"
  fi

  systemctl daemon-reload || true
  if systemctl enable --now wg-autoswitch.timer 2>/dev/null; then
    log "Enabled via systemd timer."
  elif systemctl enable --now wg-autoswitch.service 2>/dev/null; then
    log "Enabled via systemd service (no timer)."
  else
    warn "systemd present but enabling failed; falling back to cron."
    USE_CRON=1
  fi
else
  USE_CRON=1
fi

# 4) Cron fallback (root): every 2 minutes
if [ "${USE_CRON:-0}" = "1" ]; then
  # Prefer a dedicated file in /etc/cron.d (works even if no user crontab yet)
  if [ -d /etc/cron.d ]; then
    tee /etc/cron.d/wg-autoswitch >/dev/null <<EOF
*/2 * * * * root $RUNNER_DST >/dev/null 2>&1
EOF
    chmod 0644 /etc/cron.d/wg-autoswitch
    log "Enabled via /etc/cron.d/wg-autoswitch (every 2 min)."
  else
    # Fallback to root’s crontab
    (crontab -l 2>/dev/null | grep -v "$RUNNER_DST" || true; echo "*/2 * * * * $RUNNER_DST >/dev/null 2>&1") | crontab -
    log "Enabled via root crontab (every 2 min)."
  fi
fi
