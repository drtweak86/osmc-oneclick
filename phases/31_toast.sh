#!/usr/bin/env bash
set -euo pipefail

toast_notify() {
  local flag_img="$HOME/.kodi/media/notify/flags/$1.png"  # e.g. "gb" -> ~/.kodi/.../gb.png
  local text="🦈 $2 $3 ${4}Mbps"
  if command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(VPN Switch,${text},5000,${flag_img})" >/dev/null 2>&1
  else
    echo "[toast] ${text}"
  fi
}
