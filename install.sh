#!/usr/bin/env bash
set -euo pipefail

# Re-run as root if needed
[ "${EUID:-$(id -u)}" -ne 0 ] && exec sudo -E bash "$0" "$@"

log(){ echo -e "[oneclick] $*"; }

# Make sure all phase scripts are executable (web uploads can lose +x)
chmod +x /opt/osmc-oneclick/install.sh /opt/osmc-oneclick/phases/*.sh 2>/dev/null || true

# Ordered phases:
# - helpers first (functions env)
# - VPN setup, autoswitch + toast
# - weekly maintenance, backups
# - addons and skin setup
PHASES=(
  31_helpers.sh
  10_maintenance.sh
  20_optimize.sh
  30_vpn.sh
  31_vpn_autoswitch.sh
  31_toast.sh
  32_enable_autoswitch.sh
  40_maintenance.sh
  41_backup.sh
  42_addons.sh
  43_skin_exo2.sh
)

for phase in "${PHASES[@]}"; do
  script="/opt/osmc-oneclick/phases/$phase"
  if [ -x "$script" ]; then
    log "Running $phase"
    bash "$script"
  else
    log "Skipping missing $phase"
  fi
done

log "All done."
