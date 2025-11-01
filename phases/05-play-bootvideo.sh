#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
set -euo pipefail
VID="/boot/matrix_boot.mp4"
[ -f "$VID" ] || exit 0

# Wait up to ~30s for Kodi's service (OSMC/xbian use mediacenter/kodi)
SVC="mediacenter"
systemctl list-unit-files 2>/dev/null | grep -q "^kodi\.service" && SVC="kodi"

for i in {1..30}; do
  systemctl is-active --quiet "$SVC" && break
  sleep 1
done
# small extra settle
sleep 3

# Fire and stop after 8s
kodi-send --action="PlayMedia($VID)" || exit 0
sleep 8
kodi-send --action="PlayerControl(Stop)" || true
