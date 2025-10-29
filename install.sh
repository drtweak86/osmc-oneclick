#!/usr/bin/env bash
set -euo pipefail
[ "$EUID" -ne 0 ] && exec sudo -E bash "$0" "$@"

log(){ echo -e "[oneclick] $*"; }

# Ensure scripts are executable (useful when created via GitHub web)
chmod +x /opt/osmc-oneclick/install.sh /opt/osmc-oneclick/phases/*.sh 2>/dev/null || true

# Phase order
for phase in 10_maintenance.sh 20_optimize.sh 30_vpn.sh 31_vpn_autoswitch.sh 32_enable_autoswitch.sh; do
  if [ -x "/opt/osmc-oneclick/phases/$phase" ]; then
    log "Running $phase"
    bash "/opt/osmc-oneclick/phases/$phase"
  else
    log "Skipping missing $phase"
  fi
done

log "All done."
