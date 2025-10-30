#!/usr/bin/env bash
# Build an XBian image with OneClick baked in (phases + assets + defaults)
# Usage: sudo ./build-oneclick-image.sh XBIAN.img [OUTPUT.img.gz]
set -euo pipefail

SRC_IMG="${1:-}"
OUT="${2:-xbian-oneclick.img.gz}"

if [[ -z "$SRC_IMG" || ! -f "$SRC_IMG" ]]; then
  echo "[build] Usage: $0 XBIAN.img [OUTPUT.img.gz]" >&2
  exit 1
fi

# ---- repo roots (relative to this script) ----
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SELF_DIR/.." && pwd)"

PHASES_SRC="$ROOT_DIR/phases"
ASSETS_SRC="$ROOT_DIR/assets"
INSTALL_SRC="$ROOT_DIR/install.sh"
FIRSTBOOT_SRC="$ROOT_DIR/firstboot.sh"

# ---- required sources (preflight) ----
REQ=(
  "$INSTALL_SRC"
  "$PHASES_SRC/04_prereqs.sh"
  "$PHASES_SRC/05_pi_tune.sh"
  "$PHASES_SRC/20_optimize.sh"
  "$PHASES_SRC/22_argon_one.sh"
  "$PHASES_SRC/30_vpn.sh"
  "$PHASES_SRC/31_helpers.sh"
  "$PHASES_SRC/31_toast.sh"
  "$PHASES_SRC/31_vpn_autoswitch.sh"
  "$PHASES_SRC/32_enable_autoswitch.sh"
  "$PHASES_SRC/33_install_speedtest.sh"
  "$PHASES_SRC/33_wifi_autoswitch.sh"
  "$PHASES_SRC/40_backup.sh"
  "$PHASES_SRC/40_maintenance.sh"
  "$PHASES_SRC/41_backup.sh"
  "$PHASES_SRC/42_addons.sh"
  "$PHASES_SRC/43_fonts.sh"
  "$PHASES_SRC/44_advanced.sh"
  "$PHASES_SRC/45_kodi_qol.sh"
  "$ASSETS_SRC/config/wifi-autoswitch"
  "$ASSETS_SRC/config/wg-autoswitch"
  "$ASSETS_SRC/config/advancedsettings.xml"
  "$ASSETS_SRC/fonts/Exo2-Regular.ttf"
  "$ASSETS_SRC/fonts/Exo2-Light.ttf"
  "$ASSETS_SRC/fonts/Exo2-Bold.ttf"
  "$ASSETS_SRC/Font.xml"
)

echo "[build] Preflight check…"
MISS=0
for p in "${REQ[@]}"; do
  if [[ ! -f "$p" ]]; then echo "[build][MISS] $p"; ((MISS++)); fi
done
if (( MISS > 0 )); then
  echo "[build] Missing $MISS required file(s). Aborting." >&2
  exit 2
fi
echo "[build] All sources present ✔"

# ---- workspace ----
TMP="$(mktemp -d)"
cleanup(){ set +e; [[ -n "${LOOP:-}" ]] && losetup -d "$LOOP" 2>/dev/null || true; umount "$TMP/boot" "$TMP/root" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT

IMG_WORK="$TMP/xbian.img"
cp --reflink=auto -f "$SRC_IMG" "$IMG_WORK"

echo "[build] Attaching image…"
LOOP="$(losetup --show -Pf "$IMG_WORK")"
sleep 1
BOOT="${LOOP}p1"
ROOT="${LOOP}p2"

mkdir -p "$TMP/boot" "$TMP/root"
mount -o rw "$BOOT" "$TMP/boot"
mount -o rw "$ROOT" "$TMP/root"

# ---- lay down files ----
OC_DIR="$TMP/root/opt/osmc-oneclick"
mkdir -p "$OC_DIR"
echo "[build] Copying phases + assets + install.sh"
rsync -a --delete "$PHASES_SRC/" "$OC_DIR/phases/"
rsync -a --delete "$ASSETS_SRC/" "$OC_DIR/assets/"
install -m 0755 "$INSTALL_SRC" "$OC_DIR/install.sh"

# firstboot on /boot
FB="$TMP/boot/firstboot.sh"
if [[ -f "$FIRSTBOOT_SRC" ]]; then
  install -m 0755 "$FIRSTBOOT_SRC" "$FB"
else
  # minimal firstboot that fetches & runs installer from local /opt/osmc-oneclick
  cat >"$FB" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/firstboot.log
exec > >(tee -a "$LOG") 2>&1
echo "[firstboot] starting"
# wait for network
for i in $(seq 1 60); do ip route | grep -q '^default ' && break; sleep 2; done
# ensure ssh if present
systemctl enable --now ssh 2>/dev/null || true
systemctl enable --now dropbear 2>/dev/null || true
# run local installer (already baked)
if [[ -x /opt/osmc-oneclick/install.sh ]]; then
  bash /opt/osmc-oneclick/install.sh || true
fi
# disable self and reboot
systemctl disable oneclick-firstboot.service || true
rm -f /boot/firstboot.sh || true
sync; sleep 2; reboot
SH
  chmod +x "$FB"
fi

# ---- systemd unit (enabled) ----
UNIT_PATH="$TMP/root/etc/systemd/system/oneclick-firstboot.service"
mkdir -p "$(dirname "$UNIT_PATH")"
cat >"$UNIT_PATH" <<'EOF'
[Unit]
Description=OneClick first boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firstboot.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 "$UNIT_PATH"
mkdir -p "$TMP/root/etc/systemd/system/multi-user.target.wants"
ln -sf ../oneclick-firstboot.service \
  "$TMP/root/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"

# ---- defaults into /etc/default (for first run) ----
mkdir -p "$TMP/root/etc/default"
install -m 0644 "$ASSETS_SRC/config/wifi-autoswitch" "$TMP/root/etc/default/wifi-autoswitch"
install -m 0644 "$ASSETS_SRC/config/wg-autoswitch"   "$TMP/root/etc/default/wg-autoswitch"

# ---- niceties ----
chown -R root:root "$OC_DIR" "$TMP/root/etc/default" 2>/dev/null || true
sync

# ---- detach & compress ----
umount "$TMP/boot" "$TMP/root"
losetup -d "$LOOP"
echo "[build] Writing $OUT"
gzip -c9 "$IMG_WORK" >"$OUT"
echo "[build] Done ✔  -> $OUT"
