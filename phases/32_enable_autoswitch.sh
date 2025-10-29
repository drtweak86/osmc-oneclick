#!/usr/bin/env bash
set -euo pipefail
log(){ echo -e "[oneclick][32_enable_autoswitch] $*"; }

# Where the repo is checked out
ROOT="/opt/osmc-oneclick"

# Install/overwrite the service & timer
install -m 0644 "$ROOT/systemd/wg-autoswitch.service" /etc/systemd/system/wg-autoswitch.service
install -m 0644 "$ROOT/systemd/wg-autoswitch.timer"   /etc/systemd/system/wg-autoswitch.timer

# Make sure the autoswitch script is executable
chmod +x "$ROOT/phases/31_vpn_autoswitch.sh" || true

# Reload systemd, enable & start the timer
systemctl daemon-reload
systemctl enable --now wg-autoswitch.timer

# Show status for quick sanity
systemctl status wg-autoswitch.timer --no-pager || true
