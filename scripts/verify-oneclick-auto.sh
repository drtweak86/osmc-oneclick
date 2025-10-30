#!/usr/bin/env bash
# verify-oneclick-auto.sh
# Auto-detect SD card first; if not found, prompt for image (.img or .img.gz).
# Verifies OneClick/XBian firstboot + baked repo contents safely (read-only).

set -euo pipefail

# -------- Pretty ----------
ok(){ printf "\033[1;32mPASS\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33mWARN\033[0m %s\n" "$*"; }
fail(){ printf "\033[1;31mFAIL\033[0m %s\n" "$*"; ((++FAILS)); }
note(){ printf "\033[1;36mINFO\033[0m %s\n" "$*"; }

# -------- Globals ----------
WORKDIR="$(mktemp -d /tmp/verify-oneclick.XXXXXX)"
BOOT_MNT="$WORKDIR/boot"
ROOT_MNT="$WORKDIR/root"
IMG_TMP=""
LOOPDEV=""
KPARTX_ADDED=0
FAILS=0
PASSES=0
WARNS=0

cleanup() {
  set +e
  mountpoint -q "$BOOT_MNT" && umount "$BOOT_MNT"
  mountpoint -q "$ROOT_MNT" && umount "$ROOT_MNT"
  if [[ $KPARTX_ADDED -eq 1 && -n "${LOOPDEV:-}" ]]; then
    kpartx -d "$LOOPDEV" >/dev/null 2>&1 || true
  fi
  [[ -n "${LOOPDEV:-}" ]] && losetup -d "$LOOPDEV" >/dev/null 2>&1 || true
  [[ -n "${IMG_TMP:-}" && -f "$IMG_TMP" ]] && rm -f "$IMG_TMP"
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

require() {
  for b in "$@"; do
    command -v "$b" >/dev/null 2>&1 || { echo "Missing: $b"; exit 1; }
  done
}
require lsblk awk sed grep head tail cut sort uniq mount umount kpartx losetup gzip dd find stat

# -------- Detect SD card (prefer) ----------
detect_sd() {
  # prefer removable, not the root device, with 2+ partitions
  local rootsd
  rootsd="$(lsblk -no pkname "$(df / | tail -1 | awk '{print $1}')" 2>/dev/null || true)"
  # collect candidates: rm=1 and with at least 2 children
  mapfile -t devs < <(lsblk -rpn -o NAME,RM,TYPE | awk '$2=="1" && $3=="disk"{print $1}')
  local good=()
  for d in "${devs[@]}"; do
    [[ -n "$rootsd" && "/dev/$rootsd" == "$d" ]] && continue
    # must have 2+ parts
    local parts
    parts=$(lsblk -rn "$d" -o TYPE | grep -c '^part$' || true)
    (( parts >= 2 )) || continue
    good+=("$d")
  done

  if (( ${#good[@]} == 1 )); then
    echo "${good[0]}"
    return 0
  elif (( ${#good[@]} > 1 )); then
    warn "Multiple removable disks detected; skipping auto-pick."
    return 1
  else
    return 1
  fi
}

# -------- Map source (device or image) ----------
map_device() {
  local dev="$1"
  note "Using SD device: $dev (read-only)"
  # Find boot + root partitions (vfat + ext4 usually)
  local bootp rootp
  bootp="$(lsblk -rpn -o NAME,FSTYPE "$dev" | awk '$2=="vfat"{print $1}' | head -n1)"
  rootp="$(lsblk -rpn -o NAME,FSTYPE "$dev" | awk '$2=="ext4"{print $1}' | head -n1)"
  # fallback: first two partitions
  [[ -z "$bootp" ]] && bootp="$(lsblk -rpn -o NAME,TYPE "$dev" | awk '$2=="part"{print $1}' | sed -n '1p')"
  [[ -z "$rootp" ]] && rootp="$(lsblk -rpn -o NAME,TYPE "$dev" | awk '$2=="part"{print $1}' | sed -n '2p')"
  [[ -z "$bootp" || -z "$rootp" ]] && { echo "Could not find two partitions on $dev"; exit 1; }
  mkdir -p "$BOOT_MNT" "$ROOT_MNT"
  mount -o ro "$bootp" "$BOOT_MNT"
  mount -o ro "$rootp" "$ROOT_MNT"
}

map_image() {
  local path="$1"
  local img="$path"
  if [[ "$path" =~ \.gz$ ]]; then
    note "Decompressing image to temp (streaming) …"
    IMG_TMP="$WORKDIR/image.img"
    gzip -dc "$path" > "$IMG_TMP"
    img="$IMG_TMP"
  fi
  LOOPDEV="$(losetup -f --show -P "$img")"
  KPARTX_ADDED=1
  kpartx -as "$LOOPDEV"
  # Find mapped partitions
  local base loopname p1 p2
  loopname="$(basename "$LOOPDEV")"
  base="/dev/mapper/${loopname}"
  # Try p1/p2 first, fallback to loopNp1 naming
  if [[ -b "${base}p1" && -b "${base}p2" ]]; then
    p1="${base}p1"; p2="${base}p2"
  else
    # sometimes kpartx names as loopNp1 anyway; try directly
    p1="/dev/mapper/${loopname}p1"
    p2="/dev/mapper/${loopname}p2"
  fi
  [[ -b "$p1" && -b "$p2" ]] || { echo "Could not map partitions from $path"; exit 1; }
  mkdir -p "$BOOT_MNT" "$ROOT_MNT"
  mount -o ro "$p1" "$BOOT_MNT"
  mount -o ro "$p2" "$ROOT_MNT"
  note "Using image: $path"
}

# -------- Checks ----------
have() { [[ -e "$1" ]]; }
is_exec() { [[ -x "$1" ]]; }

check_file() {
  local path="$1" label="$2"
  if have "$path"; then ok "$label exists ($path)"; ((++PASSES)); else fail "$label missing ($path)"; fi
}
check_exec() {
  local path="$1" label="$2"
  if is_exec "$path"; then ok "$label executable ($path)"; ((++PASSES)); else fail "$label not executable ($path)"; fi
}
check_nocrlf() {
  local path="$1" label="$2"
  if have "$path"; then
    if grep -q $'\r' "$path"; then
      fail "$label has CRLF line endings ($path)"
    else
      ok "$label has Unix line endings ($path)"; ((++PASSES))
    fi
  fi
}

do_checks() {
  # 1) firstboot wiring
  check_file "$BOOT_MNT/firstboot.sh" "firstboot.sh"
  check_exec "$BOOT_MNT/firstboot.sh" "firstboot.sh"
  check_nocrlf "$BOOT_MNT/firstboot.sh" "firstboot.sh"

  check_file "$ROOT_MNT/etc/systemd/system/oneclick-firstboot.service" "systemd service"
  check_file "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service" "service enabled (wants link)"

  # 2) baked repo
  local base="/opt/osmc-oneclick"
  check_file "$ROOT_MNT$base/install.sh" "oneclick install.sh"
  check_file "$ROOT_MNT$base/phases/04_prereqs.sh" "phases/04_prereqs.sh"
  check_file "$ROOT_MNT$base/phases/42_addons.sh" "phases/42_addons.sh"
  check_file "$ROOT_MNT$base/phases/45_kodi_qol.sh" "phases/45_kodi_qol.sh"
  check_file "$ROOT_MNT$base/assets/config/advancedsettings.xml" "advancedsettings.xml"
  check_file "$ROOT_MNT$base/assets/config/wifi-autoswitch" "wifi-autoswitch defaults"
  check_file "$ROOT_MNT$base/assets/fonts/Exo2-Regular.ttf" "Exo2-Regular.ttf"
  check_file "$ROOT_MNT$base/assets/Font.xml" "Font.xml (skin)"

  # 3) optional binaries presence (non-fatal)
  if ! have "$ROOT_MNT/usr/bin/kodi-send"; then
    warn "kodi-send not found yet (expected before Kodi first run)"; ((++WARNS))
  else
    ok "kodi-send present"; ((++PASSES))
  fi

  # 4) partition sanity
  local pcount
  pcount="$(find "$WORKDIR" -maxdepth 1 -type d -name 'boot' -o -name 'root' | wc -l)"
  if (( pcount == 2 )); then ok "boot + root both mounted read-only"; ((++PASSES)); else fail "could not mount both partitions"; fi
}

# -------- Driver ----------
main() {
  local target="${1:-}"
  local dev=""
  if [[ -z "$target" ]]; then
    if dev="$(detect_sd)"; then
      map_device "$dev"
    else
      echo "No unique SD card detected."
      read -rp "Enter path to image (.img or .img.gz): " target
      [[ -n "$target" && -r "$target" ]] || { echo "Not readable: $target"; exit 1; }
      map_image "$target"
    fi
  else
    if [[ -b "$target" ]]; then
      map_device "$target"
    else
      [[ -r "$target" ]] || { echo "Not readable: $target"; exit 1; }
      map_image "$target"
    fi
  fi

  do_checks

  echo
  printf "Summary: \033[1;32mPASS %d\033[0m  \033[1;31mFAIL %d\033[0m  \033[1;33mWARN %d\033[0m\n" "$PASSES" "$FAILS" "$WARNS"
  if (( FAILS > 0 )); then exit 2; fi
}
main "$@"
