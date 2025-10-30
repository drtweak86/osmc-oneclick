#!/usr/bin/env bash
# OneClick packer – bundles verified image + checksum + metadata
# Creates: oneclick_<date>_<sha8>.zip and a .sha256 file
set -euo pipefail

IMG="${1:-}"
if [[ -z "$IMG" || ! -f "$IMG" ]]; then
  echo "Usage: $0 <verified-image.img>"
  exit 2
fi

DATE="$(date +%F_%H%M)"
HASH="$(sha256sum "$IMG" | awk '{print substr($1,1,8)}')"
BASE="oneclick_${DATE}_${HASH}"

echo "[*] Generating checksums..."
sha256sum "$IMG" > "${BASE}.sha256"

echo "[*] Zipping image..."
zip -9 "${BASE}.zip" "$IMG" "${BASE}.sha256"

echo "[*] Done!"
echo "   → ${BASE}.zip"
echo "   → ${BASE}.sha256"
