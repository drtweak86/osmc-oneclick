#!/usr/bin/env bash
set -euo pipefail
[ "$EUID" -ne 0 ] && exec sudo -E bash "$0" "$@"

log(){ echo -e "[oneclick] $*"; }

# Phase order: A → B → C
for phase in 10_maintenance.sh 20_optimize.sh 30_vpn.sh; do
  if [ -x "/opt/osmc-oneclick/phases/$phase" ]; then
    log "Running $phase"
    bash "/opt/osmc-oneclick/phases/$phase"
  else
    log "Skipping missing $phase"
  fi
done

log "All done. Rebooting…"
sleep 2
systemctl reboot
