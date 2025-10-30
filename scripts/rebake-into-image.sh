#!/usr/bin/env bash
# rebake-into-image.sh — inject updated /opt/osmc-oneclick into existing image
# Usage: sudo ./rebake-into-image.sh /home/admin/xbian-oneclick.img

set -euo pipefail

IMAGE="${1:-}"
[ -z "$IMAGE" ] && { echo "Usage: $0 /path/to/image.img"; exit 1; }

WORKDIR="/tmp/verify-oneclick.$RANDOM"
mkdir -p "$WORKDIR"

echo "[*] Attaching image: $IMAGE"
sudo modprobe loop
LOOP=$(sudo losetup --show -f -P "$IMAGE")

# Find root and boot partitions
ROOTPART="${LOOP}p2"
BOOTPART="${LOOP}p1"
echo "[*] Mounting rootfs and boot partitions..."
sudo mkdir -p "$WORKDIR/root" "$WORKDIR/boot"
sudo mount "$ROOTPART" "$WORKDIR/root"
sudo mount "$BOOTPART" "$WORKDIR/boot"

echo "[*] Syncing /opt/osmc-oneclick into image..."
sudo mkdir -p "$WORKDIR/root/opt/osmc-oneclick"
sudo rsync -a --delete /opt/osmc-oneclick/ "$WORKDIR/root/opt/osmc-oneclick/"

echo "[*] Injecting firstboot.sh into /boot..."
sudo cp /opt/osmc-oneclick/scripts/firstboot.sh "$WORKDIR/boot/firstboot.sh"
sudo chmod +x "$WORKDIR/boot/firstboot.sh"

echo "[*] Cleaning up..."
sudo umount "$WORKDIR/root" "$WORKDIR/boot"
sudo losetup -d "$LOOP"
rm -rf "$WORKDIR"

echo "[✓] Re-bake complete!"
