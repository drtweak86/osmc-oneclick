#!/usr/bin/env bash
set -euo pipefail

# ---- Toast + helpers (single source of truth) ----
toast_vpn_simple() {
  # Args: COUNTRY_NAME PCT SPEED_MBPS
  local country="$1" pct="$2" speed="$3"
  command -v kodi-send >/dev/null 2>&1 || return 0
  nofail kodi-send --action="Notification(VPN,${country}  ${pct}%  ${speed} Mbps,6000)" >/dev/null 2>&1 || true
}

# Country name from a WireGuard iface pattern like de-ber, nl-ams, uk-lon, us-nyc, etc.
country_name_from_iface() {
  local ifname="${1:-}" cc=""
  cc="$(printf '%s' "$ifname" | sed -n 's/^\([a-z][a-z]\)[-_].*/\1/p')"
  case "$cc" in
    de) echo "Germany" ;;
    nl) echo "Netherlands" ;;
    gb|uk) echo "United Kingdom" ;;
    us) echo "United States" ;;
    fr) echo "France" ;;
    se) echo "Sweden" ;;
    no) echo "Norway" ;;
    es) echo "Spain" ;;
    it) echo "Italy" ;;
    be) echo "Belgium" ;;
    dk) echo "Denmark" ;;
    ie) echo "Ireland" ;;
    ch) echo "Switzerland" ;;
    at) echo "Austria" ;;
    *) echo "Unknown" ;;
  esac
}

# Quality % from Mbps (cap at 100). Default scale tops out around 200 Mbps.
quality_pct_from_speed() {
  local mbps="${1%.*}"
  [[ -z "$mbps" || "$mbps" -lt 0 ]] && echo 0 && return
  local pct=$(( mbps * 100 / 200 ))
  (( pct > 100 )) && pct=100
  echo "$pct"
}

# De-duplicate VPN toasts and ignore 0-values
toast_vpn_once() {
  local cc="$1" pct="$2" dl="$3"
  if [[ -z "$cc" || -z "$pct" || -z "$dl" || "$pct" = "0" || "$dl" = "0" ]]; then
    return 0
  fi
  local state="/run/wg-autoswitch.lasttoast"
  local key="${cc}:${pct}:${dl}"
  local last=""
  [[ -f "$state" ]] && last="$(cat "$state" 2>/dev/null)"
  if [[ "$key" != "$last" ]]; then
    toast_vpn_simple "$cc" "$pct" "$dl"
    printf '%s' "$key" > "$state"
  fi
}

# Nice Kodi popup
kodi_dialog() {
  command -v kodi-send >/dev/null 2>&1 || return 0
  nofail kodi-send --action="Notification($1,$2,8000,/home/xbian/.kodi/media/notify/icons/info.png)" >/dev/null 2>&1 || true
}

# nofail CMD... : run command if present, never fail
nofail() { command -v "$1" >/dev/null 2>&1 || return 0; "$@"; }
