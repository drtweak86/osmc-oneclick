#!/usr/bin/env bash
# =============================================================================
# Xtreme v1.0 — Image Builder (XBian-based)
# - Injects two-stage first-boot:
#     Stage 1: show wizard gate, user finishes XBian wizard, reboot
#     Stage 2: run config/optimise after network is up, then mark done
# - Bakes default config files (wifi-autoswitch, wg-autoswitch)
# - Copies to OUT_IMG and gzips it; prints SHA256
#
# Usage:
#   sudo ./build-oneclick-image.sh [BASE_IMG] [OUT_IMG]
#     BASE_IMG: .img OR .img.gz (default: XBian_Latest_arm64_rpi5.img)
#     OUT_IMG : .img name to emit before gzip (default: xbian-oneclick.img)
#
# You may set LOCAL_DIR to prefer local files over GitHub fetch:
#   export LOCAL_DIR=/home/admin/osmc-oneclick
# =============================================================================
set -euo pipefail

# ----------------------------- Config ----------------------------------------
BASE_IMG="${1:-XBian_Latest_arm64_rpi5.img}"
OUT_IMG="${2:-xbian-oneclick.img}"
LOCAL_DIR="${LOCAL_DIR:-}"  # if non-empty and files exist locally, use them

RAW_BASE="https://raw.githubusercontent.com/drtweak86/osmc-oneclick/main"

# Assets to inject
URL_STAGE1_SH="${RAW_BASE}/scripts/oneclick-stage1.sh"
URL_STAGE2_SH="${RAW_BASE}/scripts/oneclick-stage2.sh"
URL_STAGE1_SVC="${RAW_BASE}/firstboot/oneclick-stage1.service"
URL_STAGE2_SVC="${RAW_BASE}/firstboot/oneclick-stage2.service"

URL_WIFI_DEF="${RAW_BASE}/assets/config/wifi-autoswitch"
URL_WG_DEF="${RAW_BASE}/assets/config/wg-autoswitch"

# ---------------------------- Helpers ----------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1"; exit 1; }; }
need losetup; need mount; need umount; need curl; need gzip; need sha256sum

die() { echo "ERROR: $*" >&2; exit 1; }

fetch() {
  # fetch <local-fallback> <url> <dest> <mode> <owner:group>
  local rel="$1" url="$2" dst="$3" mode="${4:-0644}" own="${5:-root:root}"
  if [[ -n "$LOCAL_DIR" && -f "$LOCAL_DIR/$rel" ]]; then
    sudo install -m "$mode" -o "${own%:*}" -g "${own#*:}" "$LOCAL_DIR/$rel" "$dst"
  else
    sudo curl -fsSL "$url" -o "$dst"
    sudo chown "${own%:*}:${own#*:}" "$dst"
    sudo chmod "$mode" "$dst"
  fi
}

# ---------------------------- Prep workspace ---------------------------------
work="$(mktemp -d /tmp/xbian-build.XXXXXX)"
BOOT_MNT="$work/boot"
ROOT_MNT="$work/root"
mkdir -p "$BOOT_MNT" "$ROOT_MNT"

LOOPDEV=""
TMP_BASE_IMG=""

cleanup() {
  set +e
  sync
  mountpoint -q "$BOOT_MNT" && sudo umount "$BOOT_MNT"
  mountpoint -q "$ROOT_MNT" && sudo umount "$ROOT_MNT"
  [[ -n "$LOOPDEV" ]] && sudo losetup -d "$LOOPDEV"
  [[ -n "$TMP_BASE_IMG" && -f "$TMP_BASE_IMG" ]] && rm -f "$TMP_BASE_IMG"
  rm -rf "$work"
}
trap cleanup EXIT

# ---------------------------- Resolve base image ------------------------------
if [[ ! -f "$BASE_IMG" ]]; then
  die "Base image not found: $BASE_IMG"
fi

BASE_PATH="$BASE_IMG"
case "$BASE_IMG" in
  *.gz)
    echo "[*] Decompressing base .gz into temp file…"
    TMP_BASE_IMG="$work/base.img"
    gzip -dc "$BASE_IMG" > "$TMP_BASE_IMG"
    BASE_PATH="$TMP_BASE_IMG"
    ;;
  *.img)
    ;;
  *)
    die "Unsupported base image extension (use .img or .img.gz)"
    ;;
esac

# ---------------------------- Attach & mount ----------------------------------
echo "[*] Attaching image…"
LOOPDEV="$(sudo losetup --partscan --show -f "$BASE_PATH")" || die "losetup failed"
BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"

echo "[*] Mounting partitions…"
sudo mount "$BOOT_PART" "$BOOT_MNT"
sudo mount "$ROOT_PART" "$ROOT_MNT"

# ---------------------------- Inject assets -----------------------------------
echo "[*] Installing two-stage first-boot scripts…"
sudo install -d -m 0755 "$ROOT_MNT/opt/osmc-oneclick/scripts"

# Stage 1/2 scripts (0755)
fetch "scripts/oneclick-stage1.sh" "$URL_STAGE1_SH" \
      "$ROOT_MNT/opt/osmc-oneclick/scripts/oneclick-stage1.sh" 0755 root:root
fetch "scripts/oneclick-stage2.sh" "$URL_STAGE2_SH" \
      "$ROOT_MNT/opt/osmc-oneclick/scripts/oneclick-stage2.sh" 0755 root:root

echo "[*] Installing systemd units…"
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system"
fetch "firstboot/oneclick-stage1.service" "$URL_STAGE1_SVC" \
      "$ROOT_MNT/etc/systemd/system/oneclick-stage1.service" 0644 root:root
fetch "firstboot/oneclick-stage2.service" "$URL_STAGE2_SVC" \
      "$ROOT_MNT/etc/systemd/system/oneclick-stage2.service" 0644 root:root

# Enable both at first boot
sudo install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/oneclick-stage1.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-stage1.service"
sudo ln -sf /etc/systemd/system/oneclick-stage2.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-stage2.service"

echo "[*] Baking default configs into /etc/default…"
sudo install -d -m 0755 "$ROOT_MNT/etc/default"
fetch "assets/config/wifi-autoswitch" "$URL_WIFI_DEF" \
      "$ROOT_MNT/etc/default/wifi-autoswitch" 0644 root:root
fetch "assets/config/wg-autoswitch" "$URL_WG_DEF" \
      "$ROOT_MNT/etc/default/wg-autoswitch" 0644 root:root

# Optional: a tiny readme marker so we know the image was prepared
echo "Xtreme v1.0 image prepared on $(date -Is)" | sudo tee "$ROOT_MNT/etc/xtreme-image.txt" >/dev/null

# ----------------------------- Finish up --------------------------------------
echo "[*] Sync + detach…"
sync
sudo umount "$BOOT_MNT"
sudo umount "$ROOT_MNT"
sudo losetup -d "$LOOPDEV"; LOOPDEV=""

echo "[*] Copy to ${OUT_IMG} and compress…"
cp -f "$BASE_PATH" "$OUT_IMG"
gzip -f -9 "$OUT_IMG"

echo "[*] SHA256:"
sha256sum "${OUT_IMG}.gz" | tee "${OUT_IMG}.gz.sha256"

echo "All set. Flash ${OUT_IMG}.gz to SD, boot Pi:"
echo "  • First boot → finish XBian wizard → Reboot"
echo "  • Second boot → Xtreme Stage 2 runs and optimises"
