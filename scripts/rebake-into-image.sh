#!/usr/bin/env bash
# Re-bake phases/assets/install into an existing image (handy to fix older builds)
# Usage: sudo ./rebake-into-image.sh XBIAN.img
set -euo pipefail

IMG="${1:-}"
[[ -f "$IMG" ]] || { echo "Usage: $0 XBIAN.img" >&2; exit 1; }

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SELF_DIR/.." && pwd)"
PHASES="$ROOT_DIR/phases"
ASSETS="$ROOT_DIR/assets"
INSTALL="$ROOT_DIR/install.sh"

TMP="$(mktemp -d)"; trap 'set +e; [[ -n "${LOOP:-}" ]] && losetup -d "$LOOP" 2>/dev/null; umount "$TMP/boot" "$TMP/root" 2>/dev/null; rm -rf "$TMP"' EXIT

echo "[rebake] attach"
LOOP="$(losetup --show -Pf "$IMG")"; sleep 1
mkdir -p "$TMP/boot" "$TMP/root"
mount -o rw "${LOOP}p1" "$TMP/boot"
mount -o rw "${LOOP}p2" "$TMP/root"

OC="$TMP/root/opt/osmc-oneclick"
mkdir -p "$OC"
rsync -a --delete "$PHASES/" "$OC/phases/"
rsync -a --delete "$ASSETS/" "$OC/assets/"
install -m 0755 "$INSTALL" "$OC/install.sh"

# ensure unit + defaults
UNIT="$TMP/root/etc/systemd/system/oneclick-firstboot.service"
mkdir -p "$(dirname "$UNIT")"
cat >"$UNIT" <<'EOF'
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
ln -sf ../oneclick-firstboot.service \
  "$TMP/root/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service" 2>/dev/null || true

mkdir -p "$TMP/root/etc/default"
cp -f "$ASSETS/config/wifi-autoswitch" "$TMP/root/etc/default/wifi-autoswitch"
cp -f "$ASSETS/config/wg-autoswitch"   "$TMP/root/etc/default/wg-autoswitch"

sync
umount "$TMP/boot" "$TMP/root"
losetup -d "$LOOP"
echo "[rebake] done"
