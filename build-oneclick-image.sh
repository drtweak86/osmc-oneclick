#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ================================================================
BASE_IMG="${1:-XBian_Latest_arm64_rpi5.img}"   # input .img (unzipped)
OUT_IMG="${2:-xbian-oneclick.img}"             # output .img
RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"

FIRSTBOOT_SH_URL="$RAW_BASE/firstboot/firstboot.sh"
UNIT_URL="$RAW_BASE/firstboot/oneclick-firstboot.service"
WIFI_CFG_URL="$RAW_BASE/assets/config/wifi-autoswitch"
WG_CFG_URL="$RAW_BASE/assets/config/wg-autoswitch"

# If you prefer local files instead of GitHub, set LOCAL_DIR and they’ll be used.
LOCAL_DIR="${LOCAL_DIR:-}"   # e.g. /home/you/osmc-oneclick

# === Helpers ===============================================================
need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; exit 1; }; }
need losetup; need mount; need umount; need curl; need gzip; need sha256sum

[ -f "$BASE_IMG" ] || { echo "Base image not found: $BASE_IMG"; exit 1; }

WORK="$(mktemp -d)"; BOOT_MNT="$WORK/boot"; ROOT_MNT="$WORK/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

cleanup() {
  set +e
  sync
  mountpoint -q "$BOOT_MNT" && sudo umount "$BOOT_MNT"
  mountpoint -q "$ROOT_MNT" && sudo umount "$ROOT_MNT"
  [ -n "${LOOPDEV:-}" ] && sudo losetup -d "$LOOPDEV"
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "[*] Attaching image…"
LOOPDEV="$(sudo losetup --partscan --show -f "$BASE_IMG")"
BOOT_PART="${LOOPDEV}p1"; ROOT_PART="${LOOPDEV}p2"

echo "[*] Mounting partitions…"
sudo mount "$BOOT_PART" "$BOOT_MNT"
sudo mount "$ROOT_PART" "$ROOT_MNT"

echo "[*] Writing /boot/firstboot.sh"
if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/firstboot/firstboot.sh" ]; then
  sudo install -m 0755 -o root -g root "$LOCAL_DIR/firstboot/firstboot.sh" "$BOOT_MNT/firstboot.sh"
else
  sudo curl -fsSL "$FIRSTBOOT_SH_URL" -o "$BOOT_MNT/firstboot.sh"
  sudo chmod 0755 "$BOOT_MNT/firstboot.sh"
fi

echo "[*] Writing systemd unit"
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system"
if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/firstboot/oneclick-firstboot.service" ]; then
  sudo install -m 0644 -o root -g root \
    "$LOCAL_DIR/firstboot/oneclick-firstboot.service" \
    "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
else
  sudo curl -fsSL "$UNIT_URL" -o "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
  sudo chmod 0644 "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
fi
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/oneclick-firstboot.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"

echo "[*] Baking default configs into /etc/default"
sudo install -d -m 0755 "$ROOT_MNT/etc/default"

# Wi-Fi autoswitch defaults
if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/assets/config/wifi-autoswitch" ]; then
  sudo install -m 0644 -o root -g root \
    "$LOCAL_DIR/assets/config/wifi-autoswitch" \
    "$ROOT_MNT/etc/default/wifi-autoswitch"
else
  sudo curl -fsSL "$WIFI_CFG_URL" -o "$ROOT_MNT/etc/default/wifi-autoswitch"
  sudo chmod 0644 "$ROOT_MNT/etc/default/wifi-autoswitch"
fi

# VPN autoswitch defaults
if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/assets/config/wg-autoswitch" ]; then
  sudo install -m 0644 -o root -g root \
    "$LOCAL_DIR/assets/config/wg-autoswitch" \
    "$ROOT_MNT/etc/default/wg-autoswitch"
else
  sudo curl -fsSL "$WG_CFG_URL" -o "$ROOT_MNT/etc/default/wg-autoswitch"
  sudo chmod 0644 "$ROOT_MNT/etc/default/wg-autoswitch"
fi

echo "[*] Sync + detach…"
sync
sudo umount "$BOOT_MNT"; sudo umount "$ROOT_MNT"
sudo losetup -d "$LOOPDEV"; unset LOOPDEV

echo "[*] Copy to $OUT_IMG and compress"
cp -f "$BASE_IMG" "$OUT_IMG"
gzip -f -9 "$OUT_IMG"

echo "[*] SHA256:"
sha256sum "${OUT_IMG}.gz" | tee "${OUT_IMG}.gz.sha256"

echo "All set. Flash ${OUT_IMG}.gz to SD, boot the Pi, watch the toasts, done."
