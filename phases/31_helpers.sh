# Load persistent defaults
[ -f /etc/default/wg-autoswitch ] && . /etc/default/wg-autoswitch

ICON_DEFAULT="🦈"
icon() { printf "%s" "${ICON:-$ICON_DEFAULT}"; }

flag() {
  case "$1" in
    uk-lon|uk-man) printf "🇬🇧" ;;
    nl-ams)        printf "🇳🇱" ;;
    de-ber)        printf "🇩🇪" ;;
    us-nyc)        printf "🇺🇸" ;;
    *)             printf "🏳️"  ;;
  esac
}

fmt_ms() { case "$1" in (""|*[!0-9]*) echo 9999ms ;; (*) echo "$1"ms ;; esac; }

: "${PING_TARGET:=1.1.1.1}"

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

log_smart() {
  local msg="$*"

  if [[ "$msg" =~ ^Connecting\ to\ best:\ ([A-Za-z0-9_-]+)\  ]]; then
    local b="${BASH_REMATCH[1]}"
    msg="Connecting to best: ${b} $(flag "$b") $(icon)${msg#Connecting to best: ${b}}"
  fi

  if [[ "$msg" =~ ^\ *([a-z0-9-]+)\ ping:\ avg=9999ms\ loss=0%$ ]]; then
    local b="${BASH_REMATCH[1]}"
    local vals rtt loss
    vals="$(probe_rtt "$b")"
    rtt="${vals%% *}"
    loss="${vals##* }"
    msg="$(printf '  %s ping: rtt=%s loss=%s%%' "$b" "$(fmt_ms "$rtt")" "$loss")"
  fi

  echo -e "[oneclick][31_autoswitch] $msg"
}
