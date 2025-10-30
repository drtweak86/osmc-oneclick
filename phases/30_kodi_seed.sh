#!/usr/bin/env bash
set -euo pipefail
say(){ echo "[oneclick][30_kodi_seed] $*"; }

KODI_HOME="/home/osmc/.kodi"
USERDATA="$KODI_HOME/userdata"
SRC="$(dirname "$0")/../assets/kodi/userdata"

# Only seed if file not present (don't stomp user's config)
if [ ! -f "$USERDATA/advancedsettings.xml" ]; then
  say "Seeding advancedsettings.xml"
  install -o osmc -g osmc -m 644 "$SRC/advancedsettings.xml" "$USERDATA/advancedsettings.xml"
else
  say "advancedsettings.xml already exists — leaving as is"
fi
