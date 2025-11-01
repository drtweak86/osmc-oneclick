#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
set -euo pipefail
SRC="/opt/osmc-oneclick/assets/boot/matrix_boot.mp4"
DST="/boot/matrix_boot.mp4"
if [ -f "$SRC" ] && [ ! -f "$DST" ]; then
  cp -f "$SRC" "$DST"
  sync
fi
