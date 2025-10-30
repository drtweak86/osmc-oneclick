#!/usr/bin/env bash
set -euo pipefail
BASE_PATH=""

# ==========================================================
#   ⚡ Xtreme v1.0.1 Image Builder ⚡
#   A Bat-Net Production — Powered by XBian
# ==========================================================

# ---------- Arg parsing ----------
BASE_IMG=""
OUT_IMG="Xtreme.img.gz"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_IMG="$2"; shift 2 ;;
    --out)  OUT_IMG="$2";  shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done
if [[ -z "${BASE_IMG:-}" ]]; then
  echo "Usage: sudo $0 --base <base.img|base.img.gz> [--out Xtreme.img.gz]"
  exit 1
fi

# ---------- Sanity ----------
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)"; exit 1; }
for tool in losetup rsync gzip pv whiptail; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done

# ---------- Colours + Splash ----------
cyan=$(tput setaf 6); yellow=$(tput setaf 3); reset=$(tput sgr0)
clear
echo "${cyan}"
cat <<'SPLASH'
╔════════════════════════════════════════════════════╗
║        ⚡  Xtreme v1.0 Image Builder ⚡             ║
║     Encrypt • Optimize • Deploy • Dominate         ║
║     A Bat-Net Production — Powered by XBian        ║
╚════════════════════════════════════════════════════╝
SPLASH
echo "${reset}"

# ---------- Paths / workspace ----------
REPO_ROOT="$(pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
SYSTEMD_DIR="$REPO_ROOT/systemd"
VAULT_DIR="$REPO_ROOT/encrypted-vault"
WORKDIR="/home/admin/xtreme-build-$$"
mkdir -p "$WORKDIR"
MNT_ROOT="$WORKDIR/mnt"
mkdir -p "$MNT_ROOT"
LOOP_DEV=""

cleanup() {
  set +e
  umount -lf "$MNT_ROOT/proc" "$MNT_ROOT/sys" "$MNT_ROOT/dev" "$MNT_ROOT/boot" "$MNT_ROOT" 2>/dev/null || true
  [[ -n "${LOOP_DEV}" ]] && losetup -d "$LOOP_DEV" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

emit_gauge(){ whiptail --title "⚡ Xtreme Image Builder ⚡" --gauge "$1" 8 70 0; }

# ------------------ STEP 1 (no subshell): prepare base ------------------
whiptail --title "⚡ Xtreme Image Builder ⚡" --infobox "Preparing base image …" 8 60
if [[ "$BASE_IMG" == *.gz ]]; then
  cp "$BASE_IMG" "$WORKDIR/base.img.gz"
  gunzip -f "$WORKDIR/base.img.gz"
  BASE_PATH="$WORKDIR/base.img"
else
  cp "$BASE_IMG" "$WORKDIR/base.img"
  BASE_PATH="$WORKDIR/base.img"
fi
if [[ ! -f "$BASE_PATH" ]]; then
  whiptail --title "Error" --msgbox "Base image not found at: $BASE_PATH" 8 60
  exit 1
fi

# ------------------ STEP 2: map & mount ------------------
{
  echo 20
  LOOP_DEV="$(losetup -Pf --show "$BASE_PATH")"
  BOOT_PART="${LOOP_DEV}p1"
  ROOT_PART="${LOOP_DEV}p2"
  [[ -b "$ROOT_PART" ]] || { echo "Root partition not found at $ROOT_PART" >&2; exit 1; }
  echo 30
  mount "$ROOT_PART" "$MNT_ROOT"
  if [[ -b "$BOOT_PART" ]]; then
    mkdir -p "$MNT_ROOT/boot"
    mount "$BOOT_PART" "$MNT_ROOT/boot" || true
  fi
  echo 35
} | emit_gauge "Mapping partitions & mounting …"

# ------------------ STEP 3: inject assets ------------------
{
  echo 40
  mkdir -p "$MNT_ROOT/usr/local/bin" "$MNT_ROOT/etc/systemd/system" \
           "$MNT_ROOT/etc/batnet-vpn" "$MNT_ROOT/etc/batnet-vpn-encrypted"
  install -m 755 "$SCRIPTS_DIR/wg-autoboot-fast.sh" "$MNT_ROOT/usr/local/bin/wg-autoboot-fast"
  install -m 755 "$SCRIPTS_DIR/batnet-roast.sh"     "$MNT_ROOT/usr/local/bin/batnet-roast"
  echo 48
  install -m 644 "$SYSTEMD_DIR/"*.service "$MNT_ROOT/etc/systemd/system/"
  rsync -a "$VAULT_DIR"/ "$MNT_ROOT/etc/batnet-vpn-encrypted/"
  chmod 700 "$MNT_ROOT/etc/batnet-vpn" "$MNT_ROOT/etc/batnet-vpn-encrypted"
  echo 55
} | emit_gauge "Copying scripts, services & encrypted vault …"

# ------------------ STEP 4: chroot ops ------------------
{
  echo 58
  mkdir -p "$MNT_ROOT/proc" "$MNT_ROOT/sys" "$MNT_ROOT/dev"
  mount -t proc /proc "$MNT_ROOT/proc"
  mount --rbind /sys "$MNT_ROOT/sys"
  mount --rbind /dev "$MNT_ROOT/dev"
  echo 62
  chroot "$MNT_ROOT" /bin/bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y wireguard wireguard-tools gocryptfs resolvconf nftables curl
    systemctl enable batnet-vpn-unlock.service surfshark-wg.service batnet-roast.service || true
    apt-get clean
  '
  echo 75
} | emit_gauge "Installing packages & enabling services inside image …"

# ------------------ STEP 5: unmount & compress ------------------
{
  echo 80
  umount -lf "$MNT_ROOT/proc" "$MNT_ROOT/sys" "$MNT_ROOT/dev" "$MNT_ROOT/boot" "$MNT_ROOT" 2>/dev/null || true
  [[ -n "${LOOP_DEV}" ]] && { losetup -d "$LOOP_DEV"; LOOP_DEV=""; }
  TMP_IMG="$WORKDIR/xtreme.img"
  cp "$BASE_PATH" "$TMP_IMG"
  echo 85
  ( pv -n "$TMP_IMG" | gzip -9 > "$OUT_IMG" ) 2>&1 \
    | whiptail --title "⚡ Xtreme Image Builder ⚡" --gauge "Compressing to $OUT_IMG …" 8 70 0
  echo 95
} | emit_gauge "Finalizing image …"

# ------------------ STEP 6: checksum ------------------
{
  echo 97
  sha256sum -b "$OUT_IMG" | tee "${OUT_IMG}.sha256" >/dev/null
  echo 100
} | emit_gauge "Generating SHA256 checksum …"

# ------------------ STEP 7: flash prompt ------------------
FLASH_DEFAULT="/dev/mmcblk0"
MSG_DONE="✅ Build complete!

Output:
  $(realpath "$OUT_IMG")
Checksum:
  $(cut -d' ' -f1 "${OUT_IMG}.sha256")

Would you like to flash this image to an SD card now?"
if whiptail --title "⚡ Xtreme Image Builder ⚡" --yesno "$MSG_DONE" 15 70; then
  DEVICES=$(lsblk -dpno NAME,RM,SIZE,MODEL | awk '$2==1 {printf "%s %s \"%s %s\"\n",$1,$1,$3,$4}')
  [[ -z "$DEVICES" ]] && { whiptail --title "Flash" --msgbox "No removable devices found." 8 50; exit 0; }
  CHOICE=$(whiptail --title "Select Target" --menu "Choose SD/USB target" 20 70 10 $DEVICES 3>&1 1>&2 2>&3) || exit 0
  if whiptail --title "Confirm Flash" --yesno "⚠️  This will ERASE $CHOICE.\n\nProceed?" 10 60; then
    UNCOMP_BYTES=$(gzip -l "$OUT_IMG" | awk 'NR==2{print $2}')
    ( gunzip -c "$OUT_IMG" | pv -n -s "$UNCOMP_BYTES" | dd of="$CHOICE" bs=4M conv=fsync status=none ) 2>&1 \
      | whiptail --title "Flashing $CHOICE" --gauge "Writing image to $CHOICE …" 8 70 0
    sync
    clear
    echo "${yellow}"; apt -qq moo || { echo "         (__)
         (oo)
  /-------\\/ 
 / |     ||  
*  ||----||  
   ^^    ^^  
   MOOOOO!   "; echo -e "\a"; }
    echo "${cyan}"
    cat <<'BOX'
╔══════════════════════════════════════╗
║  ✅  Xtreme.img.gz — Ready to Rule  ║
║  Flash complete. Safe to remove SD.  ║
╚══════════════════════════════════════╝
BOX
    echo "${reset}"
  else
    whiptail --title "Cancelled" --msgbox "Flash cancelled.\nImage left at:\n$(realpath "$OUT_IMG")" 10 60
  fi
else
  whiptail --title "⚡ Xtreme Image Builder ⚡" --msgbox "Goodbye.\nYour image is ready:\n$(realpath "$OUT_IMG")" 10 60
fi
