#!/usr/bin/env bash
# OneClick Image Sanity Checker — ultra verbose
# Usage:
#   sudo ./verify-oneclick-image.sh xbian-oneclick.img [sha256-file-or-literal]

set -euo pipefail

IMG="${1:-}"
SHA_ARG="${2:-}"             # optional: file path OR 64-hex literal
REPORT="${REPORT:-verify-report-$(date +%F_%H%M%S).txt}"

if [[ -z "$IMG" || ! -f "$IMG" ]]; then
  echo "Usage: $0 <image.img> [<sha256-file-or-literal>]"
  exit 2
fi

PASS=0; FAIL=0; WARN=0
p(){ printf "%b\n" "$*"; echo -e "$*" >>"$REPORT"; }
ok(){   PASS=$((PASS+1)); p "✅  $*"; }
bad(){  FAIL=$((FAIL+1)); p "❌  $*"; }
warn(){ WARN=$((WARN+1)); p "⚠️  $*"; }

p "=== OneClick Verify: $(date) ==="
p "Image: $IMG"
p "Report: $REPORT"
echo >>"$REPORT"

# --- SHA256 (optional) ---
if [[ -n "${SHA_ARG}" ]]; then
  p "[*] Verifying SHA256…"
  CALC="$(sha256sum "$IMG" | awk '{print $1}')"
  if [[ -f "$SHA_ARG" ]]; then
    EXPECTED="$(awk '{print $1}' "$SHA_ARG" | head -n1)"
  else
    EXPECTED="$SHA_ARG"
  fi
  if [[ "${CALC,,}" == "${EXPECTED,,}" ]]; then
    ok "SHA256 matches: $CALC"
  else
    bad "SHA256 mismatch! calc=$CALC expected=$EXPECTED"
  fi
else
  warn "No SHA256 provided. Skipping checksum verification."
fi
echo >>"$REPORT"

# --- Attach & mount image (read-only) ---
TMP_BOOT="$(mktemp -d /tmp/ocv-boot.XXXXXX)"
TMP_ROOT="$(mktemp -d /tmp/ocv-root.XXXXXX)"
LOOPDEV=""

cleanup(){
  { mountpoint -q "$TMP_BOOT" && sudo umount "$TMP_BOOT"; } || true
  { mountpoint -q "$TMP_ROOT" && sudo umount "$TMP_ROOT"; } || true
  [[ -n "$LOOPDEV" ]] && sudo losetup -d "$LOOPDEV" 2>/dev/null || true
  rmdir "$TMP_BOOT" "$TMP_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

p "[*] Attaching image with losetup…"
LOOPDEV="$(sudo losetup -fP --show "$IMG")" || { bad "losetup failed"; exit 1; }
p "    loopdev: $LOOPDEV"

BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"
if ! ls "${BOOT_PART}" "${ROOT_PART}" >/dev/null 2>&1; then
  mapfile -t PARTS < <(ls ${LOOPDEV}p* 2>/dev/null | sort)
  [[ ${#PARTS[@]} -ge 2 ]] || { bad "Unable to detect boot/root partitions"; exit 1; }
  BOOT_PART="${PARTS[0]}"; ROOT_PART="${PARTS[1]}"
  warn "Non-standard layout — guessed boot=$BOOT_PART root=$ROOT_PART"
fi

sudo mount -o ro "$BOOT_PART" "$TMP_BOOT"
sudo mount -o ro "$ROOT_PART" "$TMP_ROOT"
ok "Mounted boot -> $TMP_BOOT, root -> $TMP_ROOT"
echo >>"$REPORT"

# --- Helpers ---
must_exist(){ sudo test -e "$2" && ok "$1 present ($2)" || bad "$1 missing ($2)"; }
must_file_exec(){
  local desc="$1" path="$2"
  if sudo test -f "$path"; then
    sudo head -n1 "$path" | grep -q '^#!' || warn "$desc has no shebang ($path)"
    sudo test -x "$path" && ok "$desc executable ($(sudo stat -c '%A %a' "$path"))" \
                         || bad "$desc not executable ($(sudo stat -c '%A %a' "$path"))"
  else
    bad "$desc missing ($path)"
  fi
}

# --- Checks ---
must_file_exec "firstboot script" "$TMP_BOOT/firstboot.sh"

UNIT="$TMP_ROOT/etc/systemd/system/oneclick-firstboot.service"
WANT="$TMP_ROOT/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service"
must_exist "systemd unit" "$UNIT"
if sudo test -L "$WANT"; then ok "unit enabled (wants symlink)"; else bad "unit not enabled (missing wants symlink)"; fi

if command -v systemd-analyze >/dev/null 2>&1 && systemd-analyze --help | grep -q -- '--root'; then
  if systemd-analyze verify --root="$TMP_ROOT" "/etc/systemd/system/oneclick-firstboot.service" >/dev/null 2>&1; then
    ok "systemd unit verifies cleanly (systemd-analyze --root)"
  else
    bad "systemd unit failed verify"
  fi
else
  warn "systemd-analyze (--root) not available; skipped unit verify"
fi

if sudo test -x "$TMP_ROOT/usr/bin/kodi-send"; then ok "kodi-send present (GUI toasts)"; else warn "kodi-send not found"; fi

must_exist "oneclick phases dir" "$TMP_ROOT/opt/osmc-oneclick/phases"
must_exist "oneclick assets dir" "$TMP_ROOT/opt/osmc-oneclick/assets"
must_exist "wifi-autoswitch defaults" "$TMP_ROOT/etc/default/wifi-autoswitch"
must_exist "vpn-autoswitch defaults"  "$TMP_ROOT/etc/default/wg-autoswitch"

if sudo test -f "$TMP_BOOT/config.txt"; then
  if sudo grep -Eq '^[[:space:]]*include[[:space:]]+config\.txt\.d/\*\.conf' "$TMP_BOOT/config.txt"; then
    ok "/boot/config.txt includes config.txt.d/*.conf"
  else
    warn "/boot/config.txt lacks include (may be added on first run)"
  fi
fi

CRLF=0
for f in "$TMP_BOOT/firstboot.sh" "$UNIT"; do
  sudo grep -q $'\r' "$f" 2>/dev/null && { CRLF=1; bad "CRLF line endings in $(basename "$f")"; }
done
[[ $CRLF -eq 0 ]] && ok "No CRLF line endings in critical scripts"

USED="$(df -h "$TMP_ROOT" | awk 'NR==2{print $3"/"$2 " used"}')"
ok "Rootfs size: $USED"

echo >>"$REPORT"
p "=== SUMMARY ==="
p "PASS: $PASS   FAIL: $FAIL   WARN: $WARN"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
