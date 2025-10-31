#!/usr/bin/env bash
set -euo pipefail

STATE=/var/lib/oneclick
mkdir -p "$STATE"

# mark we reached stage1
echo "stage1: $(date -Is)" > "$STATE/stage1.reached"

# friendly on-screen notes via Kodi
if command -v kodi-send >/dev/null 2>&1; then
  kodi-send --action="Notification(Xtreme Setup,Welcome! Configure network in XBian wizard,10000)"
  kodi-send --action="Notification(Xtreme Setup,When finished choose Reboot. Setup continues after reboot.,12000)"
  # optionally jump the user to Network page if Kodi is up:
  kodi-send --action="ActivateWindow(settings,SystemSettings,return)"
fi

# also print to TTY for safety
echo ">>> Xtreme: Finish XBian wizard (network etc.), then REBOOT."
echo ">>> After reboot, setup continues automatically."

# create a flag so stage2 knows we already displayed the gate
touch "$STATE/wizard-gate.shown"

# nothing else to do on this boot
exit 0
