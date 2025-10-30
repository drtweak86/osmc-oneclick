#!/usr/bin/env bash
set -euo pipefail

usage(){ echo "Usage: $0 --basepath <path> --workdir <path> --repo <repo-root>"; exit 1; }
BASE_PATH=""; WORKDIR=""; REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --basepath) BASE_PATH="$2"; shift 2 ;;
    --workdir)  WORKDIR="$2";  shift 2 ;;
    --repo)     REPO="$2";     shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$BASE_PATH" && -n "$WORKDIR" && -n "$REPO" ]] || usage

command -v losetup >/dev/null || { echo "losetup missing"; exit 1; }
command -v rsync   >/dev/null || { echo "rsync missing"; exit 1; }

SCRIPTS_DIR="$REPO/scripts"
SYSTEMD_DIR="$REPO/systemd"
VAULT_DIR="$REPO/encrypted-vault"
for d in "$SCRIPTS_DIR" "$SYSTEMD_DIR" "$VAULT_DIR"; do
  [[ -d "$d" ]] || { echo "Missing dir: $d" >&2; exit 1; }
done
[[ -f "$SCRIPTS_DIR/wg-autoboot-fast.sh" ]] || { echo "Missing wg-autoboot-fast.sh"; exit 1; }
[[ -f "$SCRIPTS_DIR/batnet-roast.sh"     ]] || { echo "Missing batnet-roast.sh"; exit 1; }

MNT="$WORKDIR/mnt"; mkdir -p "$MNT"

# Map & mount
LOOP="$(losetup -Pf --show "$BASE_PATH")"
BOOT="${LOOP}p1"; ROOT="${LOOP}p2"
[[ -b "$ROOT" ]] || { echo "No root partition at $ROOT"; exit 1; }
mount "$ROOT" "$MNT"
if [[ -b "$BOOT" ]]; then mkdir -p "$MNT/boot"; mount "$BOOT" "$MNT/boot" || true; fi

# Inject assets
mkdir -p "$MNT/usr/local/bin" "$MNT/etc/systemd/system" \
         "$MNT/etc/batnet-vpn" "$MNT/etc/batnet-vpn-encrypted"

install -m 755 "$SCRIPTS_DIR/wg-autoboot-fast.sh" "$MNT/usr/local/bin/wg-autoboot-fast"
install -m 755 "$SCRIPTS_DIR/batnet-roast.sh"     "$MNT/usr/local/bin/batnet-roast"
install -m 644 "$SYSTEMD_DIR/"*.service           "$MNT/etc/systemd/system/"

rsync -a "$VAULT_DIR"/ "$MNT/etc/batnet-vpn-encrypted/"
chmod 700 "$MNT/etc/batnet-vpn" "$MNT/etc/batnet-vpn-encrypted"

# Chroot: install deps & enable units
mount -t proc /proc "$MNT/proc"
mount --rbind /sys  "$MNT/sys"
mount --rbind /dev  "$MNT/dev"

chroot "$MNT" /bin/bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y wireguard wireguard-tools gocryptfs resolvconf nftables curl
  systemctl enable batnet-vpn-unlock.service surfshark-wg.service batnet-roast.service || true
  apt-get clean
'

# Persist loopdev for packer
echo "$LOOP" > "$WORKDIR/loop.dev"

echo "Injected into $BASE_PATH via $LOOP"
