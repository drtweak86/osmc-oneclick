#!/usr/bin/env bash
# ======================================================================
#  Xtreme v1.0 Image Builder  —  Encrypt • Optimize • Deploy • Dominate
#  A Bat-Net Production — Powered by XBian
# ======================================================================

set -euo pipefail

# === CONFIG ===
BASE_IMG="${1:-XBian_Latest_arm64_rpi5.img}"     # base image
OUT_IMG="${2:-Xtreme_v1.0.img}"                   # output name (uncompressed)
RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"
LOCAL_DIR="${LOCAL_DIR:-}"                        # optional: use local repo

FIRSTBOOT_URL="$RAW_BASE/firstboot/firstboot.sh"
UNIT_URL="$RAW_BASE/firstboot/oneclick-firstboot.service"
WIFI_CFG_URL="$RAW_BASE/assets/config/wifi-autoswitch"
WG_CFG_URL="$RAW_BASE/assets/config/wg-autoswitch"

# === ASCII HEADER ===
clear
cat <<'BANNER'
╔════════════════════════════════════════════════════╗
║        ⚡   Xtreme v1.0 Image Builder ⚡             ║
║     Encrypt • Optimize • Deploy • Dominate         ║
║     A Bat-Net Production — Powered by XBian        ║
╚════════════════════════════════════════════════════╝
BANNER
echo

# === DEPENDENCY CHECK ===
DEPS=(pv gzip zip util-linux curl losetup)
MISSING=()
for pkg in "${DEPS[@]}"; do
  command -v "${pkg%% *}" >/dev/null 2>&1 || MISSING+=("$pkg")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "⚠️  Missing packages detected: ${MISSING[*]}"
  read -rp "Install them now? [Y/n] " REPLY
  [[ "$REPLY" =~ ^[Nn]$ ]] || sudo apt update && sudo apt install -y "${MISSING[@]}"
fi
echo

# === VALIDATE INPUT ===
[[ -f "$BASE_IMG" ]] || { echo "❌ Base image not found: $BASE_IMG"; exit 1; }

WORK="$(mktemp -d)"
BOOT_MNT="$WORK/boot"
ROOT_MNT="$WORK/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

cleanup() {
  set +e
  sync
  mountpoint -q "$BOOT_MNT" && sudo umount "$BOOT_MNT"
  mountpoint -q "$ROOT_MNT" && sudo umount "$ROOT_MNT"
  [[ -n "${LOOPDEV:-}" ]] && sudo losetup -d "$LOOPDEV"
  rm -rf "$WORK"
}
trap cleanup EXIT

# === STAGE 1: Mount & Inject ===
echo "[1/3] Attaching base image..."
LOOPDEV="$(sudo losetup --partscan --show -f "$BASE_IMG")"
BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

sudo mount "$BOOT_PART" "$BOOT_MNT"
sudo mount "$ROOT_PART" "$ROOT_MNT"

echo "[2/3] Injecting firstboot scripts and configs..."
sudo install -m 0755 -D "${LOCAL_DIR:+$LOCAL_DIR/firstboot/firstboot.sh}" "$BOOT_MNT/firstboot.sh" 2>/dev/null \
  || sudo curl -fsSL "$FIRSTBOOT_URL" -o "$BOOT_MNT/firstboot.sh"

sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system"
sudo install -m 0644 -D "${LOCAL_DIR:+$LOCAL_DIR/firstboot/oneclick-firstboot.service}" \
  "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service" 2>/dev/null \
  || sudo curl -fsSL "$UNIT_URL" -o "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"

sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/oneclick-firstboot.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"

for cfg in wifi-autoswitch wg-autoswitch; do
  SRC="${LOCAL_DIR:+$LOCAL_DIR/assets/config/$cfg}"
  DEST="$ROOT_MNT/etc/default/$cfg"
  sudo install -d -m 0755 "$(dirname "$DEST")"
  [[ -f "$SRC" ]] && sudo install -m 0644 "$SRC" "$DEST" \
    || sudo curl -fsSL "$RAW_BASE/assets/config/$cfg" -o "$DEST"
done

sync
sudo umount "$BOOT_MNT"
sudo umount "$ROOT_MNT"
sudo losetup -d "$LOOPDEV"
unset LOOPDEV

# === STAGE 2: Compress with progress ===
echo "[3/3] Compressing to ${OUT_IMG}.gz"
pv "$BASE_IMG" | gzip -9 > "${OUT_IMG}.gz"

echo
echo "✅  Image built successfully!"
sha256sum "${OUT_IMG}.gz" | tee "${OUT_IMG}.gz.sha256"
echo
read -rp "Would you like to flash it to SD now? [y/N] " FLASH
if [[ "$FLASH" =~ ^[Yy]$ ]]; then
  DEV="/dev/mmcblk0"
  echo "Flashing to $DEV..."
  pv "${OUT_IMG}.gz" | gunzip | sudo dd of="$DEV" bs=4M conv=fsync status=progress
  sync
  echo "🎉 Flash complete! Safe to eject."
else
  echo "Done. Image saved as ${OUT_IMG}.gz"
fi
