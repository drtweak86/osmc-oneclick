#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/44_advanced.sh
# Install advancedsettings.xml from assets/config (no cache overrides for Kodi 21+).
# - Idempotent (skips if unchanged)
# - Atomic replace with backup
# - Optional XML sanity check if xmllint is available

set -euo pipefail

# Helpers (log/warn/kodi_dialog)
. "$(dirname "$0")/31_helpers.sh"

USER="${USER:-xbian}"
KODI_HOME="/home/${USER}/.kodi"
USERDATA="${KODI_HOME}/userdata"

# Allow BASE_DIR override, otherwise default
BASE_DIR="${BASE_DIR:-/opt/xbian-oneclick}"
ASSET_AS="${BASE_DIR}/assets/config/advancedsettings.xml"
DEST_AS="${USERDATA}/advancedsettings.xml"

log "[advanced] Preparing to install advancedsettings.xml"
log "[advanced] Source: ${ASSET_AS}"
log "[advanced] Dest:   ${DEST_AS}"

# --- Sanity checks ---
if [[ ! -f "${ASSET_AS}" ]]; then
  warn "[advanced] Source file not found; skipping."
  exit 0
fi

# Optional: XML validation if tool exists
if command -v xmllint >/dev/null 2>&1; then
  if ! xmllint --noout "${ASSET_AS}" 2>/dev/null; then
    warn "[advanced] XML validation failed; aborting to avoid a broken config."
    exit 1
  fi
fi

mkdir -p "${USERDATA}"

# If unchanged, skip
if [[ -f "${DEST_AS}" ]] && cmp -s "${ASSET_AS}" "${DEST_AS}"; then
  log "[advanced] Already up to date; nothing to do."
  exit 0
fi

# Backup existing, if any
if [[ -f "${DEST_AS}" ]]; then
  BAK="${DEST_AS}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "${DEST_AS}" "${BAK}" || true
  log "[advanced] Backed up existing to ${BAK}"
fi

# Atomic install (write to temp then move)
TMP="$(mktemp "${DEST_AS}.XXXXXX")"
install -o "${USER}" -g "${USER}" -m 0644 "${ASSET_AS}" "${TMP}"
mv -f "${TMP}" "${DEST_AS}"

# Ensure ownership on userdata (defensive)
chown -R "${USER}:${USER}" "${KODI_HOME}" || true

# Nice toast in Kodi if available
if command -v kodi-send >/dev/null 2>&1; then
  sudo -u "${USER}" kodi-send -a "Notification(Advanced,advancedsettings.xml installed,6000)" || true
fi

log "[advanced] Installed advancedsettings.xml successfully."
exit 0
