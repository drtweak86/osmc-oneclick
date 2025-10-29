# Load persistent defaults
[ -f /etc/default/wg-autoswitch ] && . /etc/default/wg-autoswitch

# Emoji/icon defaults
ICON_DEFAULT="🦈"
icon() { printf "%s" "${ICON:-$ICON_DEFAULT}"; }

# Flag for locations shown in logs
flag() {
  case "$1" in
    uk-lon|uk-man) printf "🇬🇧" ;;
    nl-ams)        printf "🇳🇱" ;;
    de-ber)        printf "🇩🇪" ;;
    us-nyc)        printf "🇺🇸" ;;
    *)             printf "🏳️"  ;;
  esac
}

# Format RTT ms safely
fmt_ms() { case "$1" in (""|*[!0-9]*) echo 9999ms ;; (*) echo "$1"ms ;; esac; }

# Which host to ping through a tunnel to assess quality
: "${PING_TARGET:=1.1.1.1}"

# Probe RTT (ms) and loss (%) through a specific interface
# Usage: probe_rtt IFACE -> prints "rtt_ms loss_pct"
probe_rtt() {
  local iface="$1" rtt loss line avg
  if line="$(ping -I "$iface" -c 3 -w 3 -n "$PING_TARGET" 2>/dev/null | tail -n2)"; then
    loss="$(printf '%s\n' "$line" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"
    avg="$(printf '%s\n' "$line" | sed -n 's/.*= \([0-9.]\+\)\/\([0-9.]\+\)\/.*/\2/p')"
    rtt="${avg%.*}"; [ -z "$rtt" ] && rtt="9999"
    [ -z "$loss" ] && loss="0"
  else
    rtt="9999"; loss="0"
  fi
  printf '%s %s\n' "$rtt" "$loss"
}

# --- NEW: Kodi toast helpers --------------------------------------------------

# Map numeric score (≈9800 good .. 20000 bad) to 0–100%
score_to_pct() {
  # Linear map: 9800 -> 100%, 20000 -> 0%
  # clamp into [0,100]
  local s="${1:-20000}" pct
  # avoid bc dependency; use awk for float and round
  pct="$(awk -v s="$s" 'BEGIN{
    # domain 9800..20000 -> range 100..0
    pct = 100.0 * (20000.0 - s) / (20000.0 - 9800.0);
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    printf("%.0f", pct);
  }')"
  printf "%s" "${pct:-0}"
}

# Show a Kodi toast if kodi-send is available
# Usage: toast_kodi iface score dl_mbps
toast_kodi() {
  command -v kodi-send >/dev/null 2>&1 || return 0
  local iface="$1" score="$2" dl="$3"
  local pct flag_ shark title
  pct="$(score_to_pct "$score")"
  flag_="$(flag "$iface")"
  shark="$(icon)"
  # We keep message blank; title carries the compact line
  title="$shark $flag_ $iface ${pct}%% ${dl}Mbps"
  kodi-send --action="Notification($title, , 5000)"
}

# --- END: Kodi toast helpers --------------------------------------------------

# Smarter log(): decorates 'Connecting to best:' and replaces placeholder pings
log() {
  local msg="$*"

  # Decorate connect decision with flag + icon
  if [[ "$msg" =~ ^Connecting\ to\ best:\ ([A-Za-z0-9_-]+)\  ]]; then
    local b="${BASH_REMATCH[1]}"
    if [[ "$msg" != *"$(flag "$b")"* ]]; then
      msg="Connecting to best: ${b} $(flag "$b") $(icon)${msg#Connecting to best: ${b}}"
    fi

    # --- NEW: parse score and speed from the tail of the line and toast
    # Look for 'dl=NNN(M|)bps' and 'score=NNNN' patterns
    if [[ "$msg" =~ dl=([0-9.]+)Mbps ]]; then
      local dl="${BASH_REMATCH[1]}"
      local score
      if [[ "$msg" =~ score=([0-9]+) ]]; then
        score="${BASH_REMATCH[1]}"
      else
        score="20000"  # worst-case fallback
      fi
      toast_kodi "$b" "$score" "$dl"
    fi
    # --- END NEW
  fi

  # Replace placeholder ping metrics with actual probe via interface
  if [[ "$msg" =~ ^\ *([a-z0-9-]+)\ ping:\ avg=9999ms\ loss=0%$ ]]; then
    local b="${BASH_REMATCH[1]}"
    local vals rtt loss
    vals="$(probe_rtt "$b")"
    rtt="${vals%% *}"
    loss="${vals##* }"
    msg="$(printf '  %s ping: avg=%s loss=%s%%' "$b" "$(fmt_ms "$rtt")" "$loss")"
  fi

  echo -e "[oneclick][31_autoswitch] $msg"
}
