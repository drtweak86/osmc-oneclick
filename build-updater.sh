#!/usr/bin/env bash
set -euo pipefail

# ==== Config via flags ====
BASE_IMG=""
OUT_IMG="Xtreme.img.gz"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_IMG="$2"; shift 2 ;;
    --out)  OUT_IMG="$2";  shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$BASE_IMG" ]]; then
  echo "Usage: sudo $0 --base <base.img|base.img.gz> [--out Xtreme.img.gz]"
  exit 1
fi

# ==== Paths ====
REPO_ROOT="$(pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
SYSTEMD_DIR="$REPO_ROOT/systemd"
VAULT_DIR="$REPO_ROOT/encrypted-vault"

# ==== Sanity checks ====
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)"; exit 1; }
command -v losetup >/dev/null || { echo "losetup missing"; exit 1; }
command -v rsync   >/dev/null || { echo "rsync missing"; exit 1; }

[[ -d "$SCRIPTS_DIR" ]] || { echo "Missing scripts/ in repo"; exit 1; }
[[ -d "$SYSTEMD_DIR" ]] || { echo "Missing systemd/ in repo"; exit 1; }
[[ -d "$VAULT_DIR"   ]] || { echo "Missing encrypted-vault/ in repo"; exit 1; }

# Required files in repo
[[ -f "$SCRIPTS_DIR/wg-autoboot-fast.sh" ]] || { echo "scripts/wg-autoboot-fast.sh missing"; exit 1; }
[[ -f "$SCRIPTS_DIR/batnet-roast.sh"     ]] || { echo "scripts/batnet-roast.sh missing"; exit 1; }
[[ -f "$SYSTEMD_DIR/batnet-vpn-unlock.service" ]] || { echo "systemd/batnet-vpn-unlock.service missing"; exit 1; }
[[ -f "$SYSTEMD_DIR/surfshark-wg.service"      ]] || { echo "systemd/surfshark-wg.service missing"; exit 1; }
[[ -f "$SYSTEMD_DIR/batnet-roast.service"      ]] || { echo "systemd/batnet-roast.service missing"; exit 1; }

# ==== Prep workspace ====
WORKDIR="$(mktemp -d)"
cleanup() {
  set +e
  mountpoint -q "$MNT_ROOT/proc" && umount -lf "$MNT_ROOT/proc"
  mountpoint -q "$MNT_ROOT/sys"  && umount -lf "$MNT_ROOT/sys"
  mountpoint -q "$MNT_ROOT/dev"  && umount -lf "$MNT_ROOT/dev"
  mountpoint -q "$MNT_ROOT/boot" && umount -lf "$MNT_ROOT/boot"
  mountpoint -q "$MNT_ROOT"      && umount -lf "$MNT_ROOT"
  [[ -n "${LOOP_DEV:-}" ]] && losetup -d "$LOOP_DEV" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

MNT_ROOT="$WORKDIR/mnt"
mkdir -p "$MNT_ROOT"

# ==== Prepare base image ====
BASE_PATH="$BASE_IMG"
if [[ "$BASE_IMG" == *.gz ]]; then
  echo "Decompressing $BASE_IMG ..."
  cp "$BASE_IMG" "$WORKDIR/base.img.gz"
  gunzip -f "$WORKDIR/base.img.gz"
  BASE_PATH="$WORKDIR/base.img"
else
  cp "$BASE_IMG" "$WORKDIR/base.img"
  BASE_PATH="$WORKDIR/base.img"
fi

# Optional checksum verify of BASE if BASE.sha256 exists
if [[ -f "BASE.sha256" ]]; then
  echo "Verifying BASE image checksum with BASE.sha256 ..."
  ( cd "$(dirname "$BASE_PATH")" && sha256sum -b "$(basename "$BASE_PATH")" ) | awk '{print $1}' > "$WORKDIR/base.sha256"
  if ! diff -q BASE.sha256 "$WORKDIR/base.sha256" >/dev/null; then
    echo "WARNING: BASE image checksum does not match BASE.sha256 (continuing anyway)."
  else
    echo "BASE checksum OK."
  fi
else
  echo "No BASE.sha256 provided; skipping base checksum verification."
fi

# ==== Map partitions ====
echo "Mapping loop device ..."
LOOP_DEV="$(losetup -Pf --show "$BASE_PATH")"
echo "Loop device: $LOOP_DEV"

# Common layout: p1=boot, p2=root
BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"
[[ -b "$ROOT_PART" ]] || { echo "Root partition not found at $ROOT_PART"; exit 1; }

# Mount root (and boot if exists)
mount "$ROOT_PART" "$MNT_ROOT"
if [[ -b "$BOOT_PART" ]]; then
  mkdir -p "$MNT_ROOT/boot"
  mount "$BOOT_PART" "$MNT_ROOT/boot" || true
fi

# ==== Copy repo assets into image ====
echo "Copying scripts & services into image ..."
mkdir -p "$MNT_ROOT/usr/local/bin" "$MNT_ROOT/etc/systemd/system" \
         "$MNT_ROOT/etc/batnet-vpn" "$MNT_ROOT/etc/batnet-vpn-encrypted"

install -m 755 "$SCRIPTS_DIR/wg-autoboot-fast.sh" "$MNT_ROOT/usr/local/bin/wg-autoboot-fast"
install -m 755 "$SCRIPTS_DIR/batnet-roast.sh"     "$MNT_ROOT/usr/local/bin/batnet-roast"

install -m 644 "$SYSTEMD_DIR/batnet-vpn-unlock.service" "$MNT_ROOT/etc/systemd/system/"
install -m 644 "$SYSTEMD_DIR/surfshark-wg.service"      "$MNT_ROOT/etc/systemd/system/"
install -m 644 "$SYSTEMD_DIR/batnet-roast.service"      "$MNT_ROOT/etc/systemd/system/"

# Copy ciphertext vault into place
rsync -a "$VAULT_DIR"/ "$MNT_ROOT/etc/batnet-vpn-encrypted/"

chmod 700 "$MNT_ROOT/etc/batnet-vpn" "$MNT_ROOT/etc/batnet-vpn-encrypted"

# ==== Prepare chroot, install deps, enable units ====
echo "Binding /dev,/proc,/sys for chroot ..."
mount -t proc /proc "$MNT_ROOT/proc"
mount --rbind /sys  "$MNT_ROOT/sys"
mount --rbind /dev  "$MNT_ROOT/dev"

echo "Installing required packages inside image ..."
chroot "$MNT_ROOT" /bin/bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wireguard wireguard-tools gocryptfs resolvconf nftables curl
apt-get clean
'

echo "Enabling units inside image ..."
chroot "$MNT_ROOT" /bin/bash -c '
set -e
systemctl enable batnet-vpn-unlock.service || true
systemctl enable surfshark-wg.service      || true
systemctl enable batnet-roast.service      || true
# Fallback if systemctl isn’t happy in chroot: create wants symlinks
mkdir -p /etc/systemd/system/multi-user.target.wants
for u in batnet-vpn-unlock.service surfshark-wg.service batnet-roast.service; do
  [ -e "/etc/systemd/system/$u" ] && ln -sf "../$u" "/etc/systemd/system/multi-user.target.wants/$u" || true
done
'

# ==== Unmount and pack ====
echo "Finalizing image ..."
umount -lf "$MNT_ROOT/proc" || true
umount -lf "$MNT_ROOT/sys"  || true
umount -lf "$MNT_ROOT/dev"  || true
mountpoint -q "$MNT_ROOT/boot" && umount -lf "$MNT_ROOT/boot" || true
umount -lf "$MNT_ROOT"
losetup -d "$LOOP_DEV"

# Compress to output name
cp "$BASE_PATH" "$WORKDIR/xtreme.img"
echo "Compressing to $OUT_IMG ..."
gzip -9c "$WORKDIR/xtreme.img" > "$OUT_IMG"

# SHA256 of final baked image
echo "Generating SHA256 for $OUT_IMG ..."
sha256sum -b "$OUT_IMG" | tee "${OUT_IMG}.sha256"

echo "✅ Build complete."
echo "Output: $(realpath "$OUT_IMG")"
echo "SHA256: $(cut -d' ' -f1 ${OUT_IMG}.sha256)"
