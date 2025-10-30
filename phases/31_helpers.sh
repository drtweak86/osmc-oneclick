# ---- VPN toast helpers (simple country + quality + speed) ------------------

# Map interface names like de-ber, nl_ams, uk-lon, us-nyc -> country
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
    *)  echo "Unknown" ;;
  esac
}

# Convert Mbps to a rough 0–100 quality percentage (200 Mbps ceiling)
quality_pct_from_speed() {
  local mbps_raw="${1:-0}"
  # strip decimals, keep digits only
  local mbps="$(printf '%s' "$mbps_raw" | sed 's/[^0-9].*$//')"
  [ -z "$mbps" ] && echo 0 && return
  local pct=$(( mbps * 100 / 200 ))
  [ "$pct" -gt 100 ] && pct=100
  echo "$pct"
}

# Basic toast (shown for 6s)
toast_vpn_simple() {
  # Args: COUNTRY_NAME PCT SPEED_MBPS
  local country="${1:-Unknown}" pct="${2:-0}" speed="${3:-0}"
  command -v kodi-send >/dev/null 2>&1 || return 0
  kodi-send --action="Notification(VPN,${country}  ${pct}%  ${speed} Mbps,6000)"
}

# De-duplicate toasts; ignore empty/zero values
toast_vpn_once() {
  local country="${1:-}" pct="${2:-}" speed="${3:-}"
  if [ -z "$country" ] || [ -z "$pct" ] || [ -z "$speed" ] || [ "$pct" = "0" ] || [ "$speed" = "0" ]; then
    return 0
  fi
  local state="/run/wg-autoswitch.lasttoast"
  local key="${country}:${pct}:${speed}"
  local last=""
  [ -f "$state" ] && last="$(cat "$state" 2>/dev/null)"
  if [ "$key" != "$last" ]; then
    toast_vpn_simple "$country" "$pct" "$speed"
    printf '%s' "$key" > "$state"
  fi
}

# Generic Kodi dialog (still handy elsewhere)
kodi_dialog() {
  # $1 = heading, $2 = message
  command -v kodi-send >/dev/null 2>&1 || return 0
  kodi-send --action="Notification($1,$2,8000,/home/osmc/.kodi/media/notify/icons/info.png)" >/dev/null 2>&1 || true
}
# ---- End VPN toast helpers --------------------------------------------------
