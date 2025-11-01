#!/usr/bin/env bash
set -euo pipefail
SRC="/opt/xbian-oneclick/assets/boot/matrix_boot.mp4"
DST="/boot/matrix_boot.mp4"
if [ -f "$SRC" ] && [ ! -f "$DST" ]; then
  cp -f "$SRC" "$DST"
  sync
fi
