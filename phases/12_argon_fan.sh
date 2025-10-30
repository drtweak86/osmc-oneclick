#!/usr/bin/env bash
# phases/12_argon_fan.sh
# Install Argon One case fan service if present on a Pi

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

# Only attempt if it's a Raspberry Pi
if ! grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
  log "[argon] Not a Raspberry Pi device; skipping Argon fan install."
  exit 0
fi

# Argon script (official)
ARGON_SH_URL="https://download.argon40.com/argon1.sh"
TMP="/tmp/argon1.sh"

log "[argon] Downloading Argon One install script…"
curl -fsSL "$ARGON_SH_URL" -o "$TMP"
chmod +x "$TMP"

log "[argon] Running Argon One installer…"
sudo bash "$TMP" </dev/null

# Try to enable any Argon service that got installed
if systemctl list-unit-files | grep -qi 'argon*'; then
  sudo systemctl daemon-reload || true
  for svc in argon*; do
    if systemctl list-unit-files | grep -q "^$svc"; then
      log "[argon] Enabling $svc"
      sudo systemctl enable --now "$svc" || true
    fi
  done
fi

log "[argon] Completed."
