#!/usr/bin/env bash
set -euo pipefail

usage(){ echo "Usage: $0 --basepath <path> --workdir <path> --out <img.gz> [--device </dev/mmcblk0>]"; exit 1; }
BASE_PATH=""; WORKDIR=""; OUT_IMG=""; DEVICE=""; TITLE="⚡ Xtreme Image Builder ⚡"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --basepath) BASE_PATH="$2"; shift 2 ;;
    --workdir)  WORKDIR="$2";  shift 2 ;;
    --out)      OUT_IMG="$2";  shift 2 ;;
    --device)   DEVICE="$2";    shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$BASE_PATH" && -n "$WORKDIR" && -n "$OUT_IMG" ]] || usage

command -v whiptail >/dev/null || { echo "whiptail missing"; exit 1; }
command -v pv       >/dev/null || { echo "pv missing"; exit 1; }

MNT="$WORKDIR/mnt"
LOOP="$(cat "$WORKDIR/loop.dev" 2>/dev/null || true)"

# Unmount & detach
umount -lf "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/boot" "$MNT" 2>/dev/null || true
[[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null || true

# Compress with gauge
TMP_IMG="$WORKDIR/xtreme.img"
cp -f "$BASE_PATH" "$TMP_IMG"
( pv -n "$TMP_IMG" | gzip -9 > "$OUT_IMG" ) 2>&1 \
  | whiptail --title "$TITLE" --gauge "Compressing to $OUT_IMG …" 8 70 0

# Checksum
sha256sum -b "$OUT_IMG" | tee "${OUT_IMG}.sha256" >/dev/null

# Offer flashing
MSG="✅ Build complete!

Output:
  $(readlink -f "$OUT_IMG")
Checksum:
  $(cut -d' ' -f1 "${OUT_IMG}.sha256")

Would you like to flash this image to an SD card now?"
if whiptail --title "$TITLE" --yesno "$MSG" 15 70; then
  # Pick device (or use provided)
  if [[ -z "${DEVICE:-}" ]]; then
    DEVICES=$(lsblk -dpno NAME,RM,SIZE,MODEL | awk '$2==1 {printf "%s %s \"%s %s\"\n",$1,$1,$3,$4}')
    [[ -z "$DEVICES" ]] && { whiptail --title "Flash" --msgbox "No removable devices found." 8 50; exit 0; }
    DEVICE=$(whiptail --title "Select Target" --menu "Choose SD/USB target" 20 70 10 $DEVICES 3>&1 1>&2 2>&3) || exit 0
  fi
  [[ -b "$DEVICE" ]] || { whiptail --title "Error" --msgbox "Device not found: $DEVICE" 8 60; exit 1; }
  if whiptail --title "Confirm Flash" --yesno "⚠️  This will ERASE $DEVICE.\n\nProceed?" 10 60; then
    UNCOMP_BYTES=$(gzip -l "$OUT_IMG" | awk 'NR==2{print $2}')
    ( gunzip -c "$OUT_IMG" | pv -n -s "$UNCOMP_BYTES" | dd of="$DEVICE" bs=4M conv=fsync status=none ) 2>&1 \
      | whiptail --title "Flashing $DEVICE" --gauge "Writing image to $DEVICE …" 8 70 0
    sync
    clear
    apt -qq moo || { echo -e "         (__)\n         (oo)\n  /-------\\/\n / |     ||\n*  ||----||\n   ^^    ^^\n   MOOOOO!\a"; }
    cat <<'BOX'
╔══════════════════════════════════════╗
║  ✅  Xtreme.img.gz — Ready to Rule  ║
║  Flash complete. Safe to remove SD.  ║
╚══════════════════════════════════════╝
BOX
  else
    whiptail --title "Cancelled" --msgbox "Flash cancelled.\nImage left at:\n$(readlink -f "$OUT_IMG")" 10 60
  fi
else
  whiptail --title "$TITLE" --msgbox "Goodbye.\nYour image is ready:\n$(readlink -f "$OUT_IMG")" 10 60
fi
