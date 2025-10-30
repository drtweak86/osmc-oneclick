#!/usr/bin/env bash
# phases/31_toast.sh
# Thin wrapper around helpers' VPN toast: adds flag icon if available.

set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/31_helpers.sh"

toast_notify() {
  # Args: iface_name speed_mbps
  local ifname="${1:-}" speed="${2:-0}"

  # Resolve country + quality from helpers
  local country pct
  country="$(country_name_from_iface "$ifname")"
  pct="$(quality_pct_from_speed "$speed")"

  # Prefer simple text-only toast (deduped)
  toast_vpn_once "$country" "$pct" "$speed"

  # Optional: if you want a flag icon toast in addition, do it *only* if icon exists
  local cc flag_img
  cc="$(printf '%s' "$ifname" | sed -n 's/^\([a-z][a-z]\)[-_].*/\1/p')"
  flag_img="/home/osmc/.kodi/media/notify/flags/${cc}.png"

  if command -v kodi-send >/dev/null 2>&1 && [ -f "$flag_img" ]; then
    kodi-send --action="Notification(VPN Switch,${country}  ${pct}%  ${speed} Mbps,5000,${flag_img})" >/dev/null 2>&1 || true
  fi
}

# If someone calls this script directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Usage: source and call toast_notify <iface> <speed_mbps>" >&2
  exit 0
fi
