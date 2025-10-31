#!/usr/bin/env bash
# ==============================================================
#   Xtreme v1.0 — OneClick Image Builder
#   Encrypt • Optimize • Deploy • Dominate
#   A Bat-Net Production — Powered by XBian
# ==============================================================
set -euo pipefail

# --- CONFIG ---------------------------------------------------
BASE_IMG="${1:-XBian_Latest_arm64_rpi5.img}"   # input .img (unzipped)
OUT_IMG="${2:-xbian-oneclick.img}"             # output .img
RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"

FIRSTBOOT_SH_URL="$RAW_BASE/firstboot/firstboot.sh"
UNIT_URL="$RAW_BASE/firstboot/oneclick-firstboot.service"
WIFI_CFG_URL="$RAW_BASE/assets/config/wifi-autoswitch"
WG_CFG_URL="$RAW_BASE/assets/config/wg-autoswitch"

# Detect current repo as LOCAL_DIR if not specified
LOCAL_DIR="${LOCAL_DIR:-$PWD}"

# --- REQUIREMENTS ---------------------------------------------
need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing: $1"; exit 1; }; }
for tool in losetup mount umount curl gzip sha256sum rsync; do
  need "$tool"
done

[ -f "$BASE_IMG" ] || { echo "❌ Base image not found: $BASE_IMG"; exit 1; }

WORK="$(mktemp -d)"
BOOT_MNT="$WORK/boot"
ROOT_MNT="$WORK/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

cleanup() {
  set +e
  sync
  mountpoint -q "$BOOT_MNT" && sudo umount "$BOOT_MNT"
  mountpoint -q "$ROOT_MNT" && sudo umount "$ROOT_MNT"
  [ -n "${LOOPDEV:-}" ] && sudo losetup -d "$LOOPDEV" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# --- BUILD STEPS ----------------------------------------------
echo "[*] Attaching image..."
LOOPDEV="$(sudo losetup --partscan --show -f "$BASE_IMG")"
BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

echo "[*] Mounting partitions..."
sudo mount "$BOOT_PART" "$BOOT_MNT"
sudo mount "$ROOT_PART" "$ROOT_MNT"

# --- FIRSTBOOT ------------------------------------------------
echo "[*] Installing two-stage first-boot scripts..."
if [ -f "$LOCAL_DIR/firstboot/firstboot.sh" ]; then
  sudo install -m 0755 "$LOCAL_DIR/firstboot/firstboot.sh" "$BOOT_MNT/firstboot.sh"
else
  sudo curl -fsSL "$FIRSTBOOT_SH_URL" -o "$BOOT_MNT/firstboot.sh"
  sudo chmod 0755 "$BOOT_MNT/firstboot.sh"
fi

# --- SYSTEMD UNIT ---------------------------------------------
echo "[*] Installing systemd units..."
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system"
if [ -f "$LOCAL_DIR/firstboot/oneclick-firstboot.service" ]; then
  sudo install -m 0644 "$LOCAL_DIR/firstboot/oneclick-firstboot.service" \
    "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
else
  sudo curl -fsSL "$UNIT_URL" -o "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
  sudo chmod 0644 "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
fi

sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/oneclick-firstboot.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"

# --- DEFAULT CONFIGS ------------------------------------------
echo "[*] Baking default configs into /etc/default..."
sudo install -d -m 0755 "$ROOT_MNT/etc/default"

# Wi-Fi autoswitch defaults
if [ -f "$LOCAL_DIR/assets/config/wifi-autoswitch" ]; then
  sudo install -m 0644 "$LOCAL_DIR/assets/config/wifi-autoswitch" "$ROOT_MNT/etc/default/wifi-autoswitch"
else
  sudo curl -fsSL "$WIFI_CFG_URL" -o "$ROOT_MNT/etc/default/wifi-autoswitch"
  sudo chmod 0644 "$ROOT_MNT/etc/default/wifi-autoswitch"
fi

# VPN autoswitch defaults
if [ -f "$LOCAL_DIR/assets/config/wg-autoswitch" ]; then
  sudo install -m 0644 "$LOCAL_DIR/assets/config/wg-autoswitch" "$ROOT_MNT/etc/default/wg-autoswitch"
else
  sudo curl -fsSL "$WG_CFG_URL" -o "$ROOT_MNT/etc/default/wg-autoswitch"
  sudo chmod 0644 "$ROOT_MNT/etc/default/wg-autoswitch"
fi

# --- ASSETS & PHASES ------------------------------------------
echo "[*] Installing /opt/osmc-oneclick assets & phases..."
sudo install -d -m 0755 "$ROOT_MNT/opt/osmc-oneclick"

if [ -d "$LOCAL_DIR/assets" ]; then
  sudo rsync -a --delete "$LOCAL_DIR/assets/" "$ROOT_MNT/opt/osmc-oneclick/assets/"
else
  sudo install -d -m 0755 "$ROOT_MNT/opt/osmc-oneclick/assets"
fi

if [ -d "$LOCAL_DIR/phases" ]; then
  sudo rsync -a --delete "$LOCAL_DIR/phases/" "$ROOT_MNT/opt/osmc-oneclick/phases/"
else
  sudo install -d -m 0755 "$ROOT_MNT/opt/osmc-oneclick/phases"
fi

# --- FINALIZE -------------------------------------------------
echo "[*] Sync + detach..."
sync
sudo umount "$BOOT_MNT"
sudo umount "$ROOT_MNT"
sudo losetup -d "$LOOPDEV"
unset LOOPDEV

echo "[*] Copy to $OUT_IMG and compress..."
cp -f "$BASE_IMG" "$OUT_IMG"
pv "$OUT_IMG" | gzip -f -9 > "${OUT_IMG}.gz"

echo "[*] SHA256:"
sha256sum "${OUT_IMG}.gz" | tee "${OUT_IMG}.gz.sha256"

echo "✅  All set!"
echo "Flash ${OUT_IMG}.gz to SD, boot Pi:"
echo "  • First boot → XBian wizard → Reboot"
echo "  • Second boot → Xtreme Stage 2 auto-optimises"
