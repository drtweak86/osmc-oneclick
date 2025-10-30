#!/usr/bin/env bash
# phases/43_fonts.sh
# Installs custom EXO2 fonts + Font.xml into Arctic Fuse 2 skin.

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

SKIN_ID="skin.arctic.fuse.2"
SKIN_PATH="/home/osmc/.kodi/addons/${SKIN_ID}"

FONTS_DIR="${SKIN_PATH}/media/fonts"
LAYOUT_DIR="${SKIN_PATH}/1080i"
FONT_FILE_SRC="/opt/osmc-oneclick/assets/Font.xml"
FONTS_SRC_DIR="/opt/osmc-oneclick/assets/fonts"

if [[ ! -d "$SKIN_PATH" ]]; then
  warn "[fonts] ${SKIN_ID} not installed yet. Skipping custom fonts."
  exit 0
fi

log "[fonts] Installing EXO2 font family into ${FONTS_DIR}"
mkdir -p "$FONTS_DIR" "$LAYOUT_DIR"

# Copy TTFs
cp -f "${FONTS_SRC_DIR}/Exo2-Regular.ttf" "$FONTS_DIR/"
cp -f "${FONTS_SRC_DIR}/Exo2-Light.ttf" "$FONTS_DIR/"
cp -f "${FONTS_SRC_DIR}/Exo2-Bold.ttf" "$FONTS_DIR/"

# Copy Font.xml layout file
cp -f "$FONT_FILE_SRC" "${LAYOUT_DIR}/Font.xml"

chown -R osmc:osmc "$SKIN_PATH"

# Kodi popup
if command -v kodi-send >/dev/null 2>&1; then
  sudo -u osmc kodi-send -a "Notification(Fonts,EXO2 fonts installed to Arctic Fuse 2,8000)" || true
fi

log "[fonts] EXO2 fonts installed successfully."
