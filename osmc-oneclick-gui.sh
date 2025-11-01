#!/usr/bin/env bash
# OSMC One-Click – GUI wrapper (fixed Pi sudo / display issue)

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
LOGDIR="$REPO/gui-logs"
mkdir -p "$LOGDIR"

need() { command -v "$1" >/dev/null 2>&1 || { xmessage "Missing tool: $1"; exit 1; }; }
for b in yad sudo bash lsblk grep awk tee; do need "$b"; done

make_log() {
  local title="$1"
  local ts; ts="$(date +%F_%H-%M-%S)"
  local safe="${title//[^A-Za-z0-9_.-]/_}"
  echo "$LOGDIR/${ts}_${safe}.log"
}

run_and_show() {
  local title="$1"; shift
  local log; log="$(make_log "$title")"
  : > "$log"

  # Launch a tail window first (keeps running even if sudo runs headless)
  yad --title="$title" \
      --width=900 --height=600 --center \
      --text-info --tail --wrap --fore=mono --fontname="Monospace 10" \
      --filename="$log" \
      --button="Close:0" &
  local YPID=$!

  # Run the command in background, redirecting output to the log
  (
    echo "=== $title @ $(date) ==="
    echo "--------------------------------------------"
    if sudo -E bash -c "cd '$REPO' && \"$@\""; then
      echo -e "\n✅ DONE @ $(date)"
    else
      echo -e "\n❌ FAILED (exit $?) @ $(date)"
    fi
    echo "--------------------------------------------"
    echo "Saved log: $log"
  ) >>"$log" 2>&1 &

  wait "$YPID" || true
}

full_install() {
  if [[ ! -f "$REPO/base-xbian.img" ]]; then
    yad --info --title="Missing base image" \
        --text="Cannot find <b>base-xbian.img</b> in:\n\n<b>$REPO</b>" \
        --width=420 --center
    return 1
  fi
  run_and_show "Build OneClick Image" "$REPO/build_oneclick.sh"
}

verify_img() {
  local img
  img="$(yad --file --title="Choose image to verify" --filename="$REPO/")" || true
  [[ -z "${img:-}" ]] && return 0
  run_and_show "Verify Image" "$REPO/verify-oneclick-image.sh" "$img"
}

package_img() {
  local img="$REPO/tmp-build/xbian-oneclick.img"
  [[ -f "$img" ]] || img="$(yad --file --title="Choose image to package" --filename="$REPO/")"
  [[ -z "${img:-}" ]] && return 0
  run_and_show "Package OneClick ZIP" "$REPO/package-oneclick.sh" "$img"
}

menu() {
  while true; do
    yad --title="OSMC One-Click Builder" \
        --width=420 --height=260 --center \
        --text="Choose what you want to do:" \
        --button="🧱 Full Install:1" \
        --button="🧩 Verify an IMG:2" \
        --button="📦 Package ZIP:4" \
        --button="❌ Exit:3"
    case $? in
      1) full_install ;;
      2) verify_img ;;
      4) package_img ;;
      3|252) exit 0 ;;
    esac
  done
}

menu
