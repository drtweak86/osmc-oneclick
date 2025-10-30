#!/usr/bin/env bash
# verify-oneclick-image.sh
# Verifies a baked OneClick XBian image (.img or .img.gz)
# - Mounts the image read-only via losetup
# - Checks firstboot.sh + systemd unit + wants/ symlink
# - Confirms /opt/osmc-oneclick (phases + assets) present
# - Confirms /etc/default/{wifi-autoswitch,wg-autoswitch}
# - Warns on CRLF line endings
# - Prints summary + returns nonzero on any FAIL

set -euo pipefail

RED=$'\e[31m'; GRN=$'\e[32m'; YLW=$'\e[33m'; RST=$'\e[0m'
pass=0; fail=0; warn=0
P() { pass=$((pass+1)); printf "${GRN}[OK]${RST} %s\n" "$*"; }
F() { fail=$((fail+1)); printf "${RED}[FAIL]${RST} %s\n" "$*"; }
W() { warn=$((warn+1)); printf "${YLW}[WARN]${RST} %s\n" "$*"; }

usage() {
  echo "Usage: $0 <image.img[.gz]> [optional.sha256]"
  exit 1
}

[ $# -ge 1 ] || usage
IMG_IN="$1"
SHA_OPT="${2:-}"

# --- temp workspace & cleanup ---
TD="$(mktemp -d -t ocv-XXXXXX)"
BOOT="$TD/boot"; ROOT="$TD/root"
mkdir -p "$BOOT" "$ROOT"
LOOP=""
IMG="$TD/image.img"
MAPPED=""

cleanup() {
  set +e
  mountpoint -q "$BOOT" && sudo umount "$BOOT"
  mountpoint -q "$ROOT" && sudo umount "$ROOT"
  if [ -n "$MAPPED" ]; then
    sudo kpartx -d "$LOOP" >/dev/null 2>&1 || true
  fi
  if [ -n "$LOOP" ]; then
    sudo losetup -d "$LOOP" >/dev/null 2>&1 || true
  fi
  rm -f "$IMG"
  rmdir "$BOOT" "$ROOT" >/dev/null 2>&1 || true
  rm -rf "$TD"
}
trap cleanup EXIT

echo "=== OneClick Verify === $(date -u)"
echo "Input: $IMG_IN"
[ -f "$IMG_IN" ] || { echo "No such file: $IMG_IN"; exit 2; }

# --- optional SHA check ---
if [ -n "$SHA_OPT" ]; then
  if [ ! -f "$SHA_OPT" ]; then
    W "SHA file not found: $SHA_OPT (skipping)"
  else
    if sha256sum -c "$SHA_OPT"; then
      P "SHA256 matches"
    else
      F "SHA256 mismatch"; echo "Aborting."; exit 3
    fi
  fi
fi

# --- prepare raw image (supports .gz) ---
case "$IMG_IN" in
  *.img)   cp -f "$IMG_IN" "$IMG";;
  *.gz)    gzip -t "$IMG_IN" && P "gzip integrity OK" || { F "gzip integrity FAILED"; exit 3; }
           gzip -cd "$IMG_IN" > "$IMG"
           ;;
  *)       F "Unsupported extension (use .img or .img.gz)"; exit 3;;
esac

# --- attach with losetup (read-only) ---
if LOOP=$(sudo losetup --find --read-only --show "$IMG"); then
  P "Attached image: $LOOP"
else
  F "losetup failed"; exit 4
fi

# Map partitions (portable: kpartx -> /dev/mapper/loopNp1)
if sudo kpartx -as "$LOOP" >/dev/null 2>&1; then
  MAPPED=1
  BOOTP="/dev/mapper/$(basename "$LOOP")p1"
  ROOTP="/dev/mapper/$(basename "$LOOP")p2"
else
  # fallback: direct /dev/loopNp1 names
  BOOTP="${LOOP}p1"
  ROOTP="${LOOP}p2"
fi

# Wait a moment so nodes appear
sleep 0.3

# --- mount ---
if sudo mount -o ro "$BOOTP" "$BOOT" 2>/dev/null; then
  P "Mounted boot -> $BOOT"
else
  F "Failed to mount boot partition ($BOOTP)"; exit 5
fi
if sudo mount -o ro "$ROOTP" "$ROOT" 2>/dev/null; then
  P "Mounted root -> $ROOT"
else
  F "Failed to mount root partition ($ROOTP)"; exit 5
fi

# --- checks ---
# 1) firstboot.sh
if [ -f "$BOOT/firstboot.sh" ]; then
  P "firstboot.sh present"
  if file "$BOOT/firstboot.sh" | grep -qi 'crlf'; then
    W "firstboot.sh has CRLF line endings"
  fi
  if [ -x "$BOOT/firstboot.sh" ]; then
    P "firstboot.sh executable"
  else
    W "firstboot.sh not executable (will still run if ExecStart uses /bin/bash)"
  fi
else
  F "firstboot.sh missing from boot"
fi

# 2) systemd unit
UNIT="$ROOT/etc/systemd/system/oneclick-firstboot.service"
if [ -f "$UNIT" ]; then
  P "systemd unit present"
else
  F "systemd unit missing: $UNIT"
fi

# 3) wants/ symlink
WANTS_DIR="$ROOT/etc/systemd/system/multi-user.target.wants"
if [ -L "$WANTS_DIR/oneclick-firstboot.service" ]; then
  P "unit enabled (wants symlink exists)"
else
  F "unit NOT enabled (no wants symlink)"
fi

# 4) OneClick phases & assets
PHASES_DIR="$ROOT/opt/osmc-oneclick/phases"
ASSETS_DIR="$ROOT/opt/osmc-oneclick/assets"
if [ -d "$PHASES_DIR" ]; then
  n=$(find "$PHASES_DIR" -maxdepth 1 -type f -name '*.sh' | wc -l | tr -d ' ')
  [ "$n" -ge 10 ] && P "phases present ($n scripts)" || W "phases count looks low ($n)"
else
  F "phases dir missing: $PHASES_DIR"
fi
if [ -d "$ASSETS_DIR" ]; then
  P "assets present"
else
  F "assets dir missing: $ASSETS_DIR"
fi

# 5) defaults for wifi + wg autoswitch
for f in wifi-autoswitch wg-autoswitch; do
  if [ -s "$ROOT/etc/default/$f" ]; then
    P "/etc/default/$f present"
  else
    F "/etc/default/$f missing or empty"
  fi
done

# 6) kodi-send presence (non-fatal, just warn if not present in rootfs)
if ! chroot "$ROOT" /usr/bin/env bash -c 'command -v kodi-send >/dev/null 2>&1' 2>/dev/null; then
  W "kodi-send not found in image (toasts will be skipped until Kodi installs/runs)"
else
  P "kodi-send available"
fi

# 7) partition sanity (2 parts)
parts=$(sudo fdisk -l "$IMG" 2>/dev/null | awk '/^Device .* Start/{p=1;next} p&&/loop/ {print}' | wc -l | tr -d ' ')
if [ "${parts:-0}" -ge 2 ]; then
  P "partition table looks sane ($parts partitions)"
else
  W "could not parse partition table cleanly"
fi

# --- summary ---
echo
echo "===== SUMMARY ====="
echo "PASS: $pass  FAIL: $fail  WARN: $warn"
[ "$fail" -eq 0 ] || exit 10
exit 0
