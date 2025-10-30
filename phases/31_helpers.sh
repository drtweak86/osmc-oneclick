
# ---- Simple VPN toast helpers ----
toast_vpn_simple() {
  # Args: COUNTRY_NAME PCT SPEED_MBPS
  local country="$1" pct="$2" speed="$3"
  # Show for 6 seconds (6000 ms). Bump if you want longer.
  kodi-send --action="Notification(VPN,${country}  ${pct}%  ${speed} Mbps,6000)"
}

country_name_from_iface() {
  # Map interface labels like de-ber, nl-ams, uk-lon, us-nyc -> country name
  case "$1" in
    de-*) echo "Germany" ;;
    nl-*) echo "Netherlands" ;;
    uk-*) echo "United Kingdom" ;;
    us-*) echo "United States" ;;
    *)    echo "Unknown" ;;
  esac
}

quality_pct_from_speed() {
  # Turn download Mbps into a rough 0–100% “quality” (cap at 100).
  # Uses a 200 Mbps ceiling; tweak if you prefer a different scale.
  local mbps="${1%.*}"
  if [ -z "$mbps" ] || ! [ "$mbps" -ge 0 ] 2>/dev/null; then
    echo 0; return
  fi
  local pct=$(( mbps * 100 / 200 ))
  [ "$pct" -gt 100 ] && pct=100
  echo "$pct"
}
# ---- End helpers ----
# --- override: robust country resolver from interface name ---
country_name_from_iface() {
  local ifname="${1:-}"
  local cc=""
  # take first two letters before '-' or '_'
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

# De-duplicate VPN toasts and ignore empty values
toast_vpn_once() {
  local cc="$1" pct="$2" dl="$3"
  # Ignore bogus/empty metrics
  if [ -z "$cc" ] || [ -z "$pct" ] || [ -z "$dl" ] || [ "$pct" = "0" ] || [ "$dl" = "0" ]; then
    return 0
  fi
  local state="/run/wg-autoswitch.lasttoast"
  local key="${cc}:${pct}:${dl}"
  local last=""
  [ -f "$state" ] && last="$(cat "$state" 2>/dev/null)"
  # Only toast if different from last shown
  if [ "$key" != "$last" ]; then
    toast_vpn_simple "$cc" "$pct" "$dl"
    printf '%s' "$key" > "$state"
  fi
}
kodi_dialog() {
  # kodi GUI modal dialog
  # $1 = heading, $2 = message
  command -v kodi-send >/dev/null 2>&1 || return 0
  kodi-send --action="Notification($1,$2,8000,/home/osmc/.kodi/media/notify/icons/info.png)" >/dev/null 2>&1 || true
}
