#!/usr/bin/env bash
# phases/44_advanced.sh
# Install advancedsettings.xml from assets/config (no legacy cache overrides)

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

USER="osmc"
KODI_HOME="/home/${USER}/.kodi"
USERDATA="${KODI_HOME}/userdata"
ASSET_AS="${BASE_DIR:-/opt/osmc-oneclick}/assets/config/advancedsettings.xml"
DEST_AS="${USERDATA}/advancedsettings.xml"

log "[advanced] Installing advancedsettings.xml"

if [[ ! -f "${ASSET_AS}" ]]; then
  warn "[advanced] ${ASSET_AS} not found. Skipping."
  exit 0
fi

mkdir -p "${USERDATA}"

# Only replace if changed; back up existing first
if [[ -f "${DEST_AS}" ]] && cmp -s "${ASSET_AS}" "${DEST_AS}"; then
  log "[advanced] Already up to date"
else
  if [[ -f "${DEST_AS}" ]]; then
    cp -a "${DEST_AS}" "${DEST_AS}.bak.$(date +%Y%m%d%H%M%S)" || true
  fi
  install -o "${USER}" -g "${USER}" -m 0644 "${ASSET_AS}" "${DEST_AS}"
  log "[advanced] Installed to ${DEST_AS}"
  if command -v kodi-send >/dev/null 2>&1; then
    sudo -u "${USER}" kodi-send -a "Notification(Advanced,advancedsettings.xml installed,6000)" || true
  fi
fi

chown -R "${USER}:${USER}" "${KODI_HOME}" || true
log "[advanced] Done."
