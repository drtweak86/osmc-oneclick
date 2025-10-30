#!/usr/bin/env bash
# phases/43_fonts.sh
# Install EXO2 (Regular/Light/Bold) + Font.xml into Arctic Fuse 2.
# Idempotent, with safety checks and optional skin reload.

set -euo pipefail

. "$(dirname "$0")/31_helpers.sh"

# --- Skin targets (first found wins) ---
CANDIDATE_SKINS=(
  "skin.arctic.fuse.2"
  # "skin.arctic.horizon.2"   # uncomment if you want to support Horizon too
)

ASSETS_ROOT="/opt/osmc-oneclick/assets"
FONT_XML_SRC="${ASSETS_ROOT}/Font.xml"
FONTS_SRC_DIR="${ASSETS_ROOT}/fonts"

# Required TTFs (exact filenames)
NEEDED_TTFS=(
  "Exo2-Regular.ttf"
  "Exo2-Light.ttf"
  "Exo2-Bold.ttf"
)

find_skin_path() {
  local sid
  for sid in "${CANDIDATE_SKINS[@]}"; do
    local p="/home/osmc/.kodi/addons/${sid}"
    if [[ -d "$p" ]]; then
      echo "$sid|$p"
      return 0
    fi
  done
  return 1
}

# --- Locate skin ---
if ! pair="$(find_skin_path)"; then
  warn "[fonts] No target skin installed yet (looked for: ${CANDIDATE_SKINS[*]}). Skipping."
  exit 0
fi
SKIN_ID="${pair%%|*}"
SKIN_PATH="${pair##*|}"

FONTS_DIR="${SKIN_PATH}/media/fonts"
LAYOUT_DIR="${SKIN_PATH}/1080i"

log "[fonts] Target skin: ${SKIN_ID}"
log "[fonts] Skin path:   ${SKIN_PATH}"

# --- Sanity: assets present? ---
if [[ ! -f "$FONT_XML_SRC" ]]; then
  warn "[fonts] Missing Font.xml in ${FONT_XML_SRC} — aborting."
  exit 1
fi
for f in "${NEEDED_TTFS[@]}"; do
  if [[ ! -f "${FONTS_SRC_DIR}/${f}" ]]; then
    warn "[fonts] Missing ${FONTS_SRC_DIR}/${f} — aborting."
    exit 1
  fi
done

# --- Install fonts + Font.xml ---
mkdir -p "$FONTS_DIR" "$LAYOUT_DIR"

log "[fonts] Copying TTFs to ${FONTS_DIR}"
for f in "${NEEDED_TTFS[@]}"; do
  cp -f "${FONTS_SRC_DIR}/${f}" "${FONTS_DIR}/"
done

log "[fonts] Placing Font.xml to ${LAYOUT_DIR}/Font.xml"
cp -f "$FONT_XML_SRC" "${LAYOUT_DIR}/Font.xml"

# --- Permissions ---
chown -R osmc:osmc "$SKIN_PATH" || true

# --- Nudge Kodi to pick up the new fonts (non-fatal if kodi-send missing) ---
if command -v kodi-send >/dev/null 2>&1; then
  sudo -u osmc kodi-send -a "Notification(Fonts,EXO2 installed for ${SKIN_ID},6000)" || true
  # Reload skin so Font.xml is re-read
  sudo -u osmc kodi-send -a "ReloadSkin()" || true
fi

log "[fonts] EXO2 fonts installed successfully for ${SKIN_ID}"
exit 0
