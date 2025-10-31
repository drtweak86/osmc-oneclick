#!/usr/bin/env bash
set -euo pipefail

# ╔════════════════════════════════════════════════════╗
# ║        ⚡   Xtreme v1.2 Image Builder ⚡             ║
# ║     Encrypt • Optimise • Deploy • Dominate          ║
# ║     A Bat-Net Production — Powered by XBian         ║
# ╚════════════════════════════════════════════════════╝

# === CONFIG ================================================================
BASE_IMG="${1:-XBian_Latest_arm64_rpi5.img}"   # input .img (unzipped)
OUT_IMG="${2:-xbian-oneclick.img}"             # output .img
RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"

FIRSTBOOT_SH_URL="$RAW_BASE/firstboot/firstboot.sh"
UNIT_URL="$RAW_BASE/firstboot/oneclick-firstboot.service"
WIFI_CFG_URL="$RAW_BASE/assets/config/wifi-autoswitch"
WG_CFG_URL="$RAW_BASE/assets/config/wg-autoswitch"

# LOCAL_DIR can override online sources if running from your repo clone
LOCAL_DIR="${LOCAL_DIR:-$PWD}"

# === Helper: dependency check ==============================================
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1"; MISSING=1; }; }

echo "[*] Checking dependencies..."
MISSING=0
for cmd in losetup mount umount curl gzip sha256sum rsync pv; do
  need "$cmd"
done

if [[ $MISSING -eq 1 ]]; then
  echo "⚠️  Missing packages detected. Run:"
  echo "   sudo apt install -y losetup curl gzip sha256sum rsync pv"
  exit 1
fi

# === Sanity ================================================================
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
  [ -n "${LOOPDEV:-}" ] && sudo losetup -d "$LOOPDEV"
  rm -rf "$WORK"
}
trap cleanup EXIT

# === Stage 1: attach & mount ==============================================
echo "[1/6] Attaching image..."
LOOPDEV="$(sudo losetup --partscan --show -f "$BASE_IMG")"
BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

echo "[2/6] Mounting partitions..."
sudo mount "$BOOT_PART" "$BOOT_MNT"
sudo mount "$ROOT_PART" "$ROOT_MNT"

# === Stage 2: inject first-boot scripts ===================================
echo "[3/6] Installing two-stage first-boot scripts..."
if [ -f "$LOCAL_DIR/firstboot/firstboot.sh" ]; then
  sudo install -m 0755 -o root -g root "$LOCAL_DIR/firstboot/firstboot.sh" "$BOOT_MNT/firstboot.sh"
else
  sudo curl -fsSL "$FIRSTBOOT_SH_URL" -o "$BOOT_MNT/firstboot.sh"
  sudo chmod 0755 "$BOOT_MNT/firstboot.sh"
fi

# === Stage 3: systemd units ===============================================
echo "[4/6] Installing systemd units..."
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system"
if [ -f "$LOCAL_DIR/firstboot/oneclick-firstboot.service" ]; then
  sudo install -m 0644 -o root -g root "$LOCAL_DIR/firstboot/oneclick-firstboot.service" "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
else
  sudo curl -fsSL "$UNIT_URL" -o "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
  sudo chmod 0644 "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service"
fi
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/oneclick-firstboot.service "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"

# === Stage 4: bake default configs ========================================
echo "[5/6] Baking default configs into /etc/default..."
sudo install -d -m 0755 "$ROOT_MNT/etc/default"
sudo install -m 0644 -o root -g root "$LOCAL_DIR/assets/config/wifi-autoswitch" "$ROOT_MNT/etc/default/wifi-autoswitch"
sudo install -m 0644 -o root -g root "$LOCAL_DIR/assets/config/wg-autoswitch" "$ROOT_MNT/etc/default/wg-autoswitch"

# === Stage 5: inject Xtreme overrides =====================================
echo "[6/6] Installing /opt/xtreme-config overrides..."
if [ -d "$LOCAL_DIR/opt/xtreme-config" ]; then
  sudo rsync -a "$LOCAL_DIR/opt/xtreme-config/" "$ROOT_MNT/opt/xtreme-config/"
  sudo chmod -R a+rX "$ROOT_MNT/opt/xtreme-config"
fi

# Ensure xbian-config prefers our wrapper
if sudo test -f "$ROOT_MNT/usr/local/sbin/xbian-config"; then
  sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/xbian-config.service.d"
  sudo tee "$ROOT_MNT/etc/systemd/system/xbian-config.service.d/override.conf" >/dev/null <<'INI'
[Service]
ExecStart=
ExecStart=/opt/xtreme-config/xbian-config-wrapper
INI
fi

# === Finalise =============================================================
echo "[*] Sync + detach..."
sync
sudo umount "$BOOT_MNT"
sudo umount "$ROOT_MNT"
sudo losetup -d "$LOOPDEV"
unset LOOPDEV

echo "[*] Compressing to ${OUT_IMG}.gz"
pv "$BASE_IMG" | gzip -9 > "${OUT_IMG}.gz"

echo "[*] SHA256 checksum:"
sha256sum "${OUT_IMG}.gz" | tee "${OUT_IMG}.gz.sha256"

echo
echo "✅ Build complete!"
echo "   → ${OUT_IMG}.gz ready to flash."
echo
echo "💡 Tip: After first boot, complete XBian wizard,"
echo "        then reboot to start Xtreme Stage-2 optimisation."
