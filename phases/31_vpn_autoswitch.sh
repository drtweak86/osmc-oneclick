#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config / defaults
# =========================
# Load optional site defaults
[ -f /etc/default/wg-autoswitch ] && . /etc/default/wg-autoswitch

# Sensible defaults if not set in /etc/default/wg-autoswitch
: "${MIN_DL_MBIT:=12}"           # Minimum acceptable downlink Mbps for streaming
: "${MAX_RTT_MS:=80}"            # Maximum acceptable average RTT in ms
: "${MAX_LOSS_PCT:=2}"           # Maximum acceptable packet loss in %
: "${TEST_BYTES:=$((4*1024*1024))}" # ~4 MB per throughput probe
: "${PING_TARGET:=1.1.1.1}"      # Ping target through each tunnel
: "${LOG_FILE:=/var/log/wg-autoswitch.log}"
: "${ICON:=🦈}"

# Candidate WireGuard interface names (must match your wg profiles)
CANDIDATES=( de-ber nl-ams uk-lon uk-man us-nyc )

# External helper to actually switch profiles (must exist already)
WG_SWITCH_BIN="/usr/local/sbin/wg-switch"

# =========================
# Logging helpers
# =========================
flag() {
  case "$1" in
    uk-lon|uk-man) printf "🇬🇧" ;;
    nl-ams)        printf "🇳🇱" ;;
    de-ber)        printf "🇩🇪" ;;
    us-nyc)        printf "🇺🇸" ;;
    *)             printf "🏳️"  ;;
  esac
}

fmt_ms() { case "$1" in (""|*[!0-9]*) echo "9999ms" ;; (*) echo "${1}ms" ;; esac; }

_log() {
  # Prints to stdout and to LOG_FILE (if writable)
  local line="[oneclick][31_autoswitch] $*"
  echo -e "$line"
  { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true; echo -e "$line"; } >>"$LOG_FILE" 2>/dev/null || true
}

log() {
  local msg="$*"
  # Decorate the “Connecting to best” line
  if [[ "$msg" =~ ^Connecting\ to\ best:\ ([A-Za-z0-9_-]+)\  ]]; then
    local b="${BASH_REMATCH[1]}"
    msg="Connecting to best: ${b} $(flag "$b") ${ICON}${msg#Connecting to best: ${b}}"
# --- Toast block ---
best_line=$(grep "Connecting to best:" /var/log/wg-autoswitch.log | tail -n1); 
cc=$(echo "$best_line" | grep -oP "(?<=Connecting to best: )[a-z]{2}"); 
dl=$(echo "$best_line" | grep -oP "dl=\K[0-9.]+"); 
sc=$(echo "$best_line" | grep -oP "score=\K[0-9]+"); 
if [ -n "$cc" ] && [ -n "$dl" ] && [ -n "$sc" ] && [ "$dl" != "0" ]; then 
  pct=$(( (20000 - sc) * 100 / 20000 )); 
  dl_int=${dl%.*}; 
  toast_vpn_once "$cc" "$pct" "$dl_int"; 
fi 
# --- end toast block ---
: "${best_name:=${current_name:-UNKNOWN}}"
: "${score_pct:=0}"
: "${dl_mbps:=0}"
toast_vpn_once "${best_name^^}" "${score_pct}" "${dl_mbps}"
  fi
  _log "$msg"
}

# =========================
# Probing functions
# =========================
probe_rtt_loss() {
  # $1 = iface (WireGuard interface name)
  local iface="$1" line loss avg rtt
  # 3 quick pings bound to interface
  if line="$(ping -I "$iface" -c 3 -w 3 -n "$PING_TARGET" 2>/dev/null | tail -n2)"; then
    loss="$(printf '%s\n' "$line" | sed -n 's/.* \([0-9.]\+\)% packet loss.*/\1/p')"
    avg="$(printf '%s\n' "$line" | sed -n 's/.*= \([0-9.]\+\)\/\([0-9.]\+\)\/.*/\2/p')"
    rtt="${avg%.*}"
    [[ -z "$rtt" ]] && rtt="9999"
    [[ -z "$loss" ]] && loss="0"
  else
    rtt="9999"; loss="0"
  fi
  printf '%s %s\n' "$rtt" "$loss"
}

probe_throughput_mbit() {
  # $1 = iface
  local iface="$1"
  # Small bounded range download against a reliable test host; 4MB default
  # If you have your own test endpoint, change URL below.
  local url="http://speed.hetzner.de/100MB.bin"
  local bytes="$TEST_BYTES"
  local start end dur_s bits_per_s mbit
  start=$(date +%s%3N)
  if curl --interface "$iface" --silent --show-error \
          --max-time 6 \
          --range 0-$((bytes-1)) \
          -o /dev/null "$url" 2>/dev/null; then
    :
  else
    # If curl fails (host blocked via that tunnel), return 0
    echo "0"
    return 0
  fi
  end=$(date +%s%3N)
  dur_ms=$((end - start))
  (( dur_ms < 1 )) && dur_ms=1
  # bits per second = bytes * 8 / (ms/1000) = bytes*8000 / ms
  bits_per_s=$(( bytes * 8000 / dur_ms ))
  # Mbit/s (integer)
  mbit=$(( bits_per_s / 1000000 ))
  echo "$mbit"
}

score_line() {
  # Produce a "score" where LOWER is better. Keep it simple & monotonic:
  # score = 10000 - dl_mbit + rtt_ms + (loss_pct * 50)
  # This keeps values around the 9800–9950 range like your prior logs.
  local rtt_ms="$1" loss_pct="$2" dl_mbit="$3"
  local loss_penalty=$(( ${loss_pct%.*} * 50 ))
  local score=$(( 10000 - dl_mbit + rtt_ms + loss_penalty ))
  echo "$score"
}

# =========================
# Switch helpers
# =========================
current_iface() {
  # Parse the single active wg iface; if multiple, pick first
  wg show | awk '/interface:/{print $2; exit}'
}

switch_to() {
  local target="$1"
  if [[ -x "$WG_SWITCH_BIN" ]]; then
    "$WG_SWITCH_BIN" "$target"
  else
    # Fallback: try to bring up profile directly if a .conf exists in /etc/wireguard
    if [[ -f "/etc/wireguard/${target}.conf" ]]; then
      # Best-effort: down current, up target
      local cur
      cur="$(current_iface || true)"
      [[ -n "$cur" && "$cur" != "$target" ]] && (wg-quick down "$cur" >/dev/null 2>&1 || true)
      wg-quick up "$target"
    else
      _log "WARN: No $WG_SWITCH_BIN and no /etc/wireguard/${target}.conf; cannot switch."
      return 1
    fi
  fi
}

# TOAST: VPN  -> Country  quality%  speed
source /opt/osmc-oneclick/phases/31_helpers.sh

# Fallbacks so we always have data
cur_if="$(wg show | awk '/interface:/{print $2; exit}')"
iface="${best_name:-$cur_if}"
speed="${best_dl:-${current_dl:-0}}"

cn="$(country_name_from_iface "$iface")"
qp="$(quality_pct_from_speed "$speed")"

toast_vpn_once "$cn" "$qp" "$speed"

# =========================
# Main
# =========================
main() {
  local cur best best_score=99999
  local -A rtt_map loss_map dl_map score_map

  cur="$(current_iface || true)"

  log "Starting VPN auto-switch check (streaming-aware: rtt≤${MAX_RTT_MS}ms, loss≤${MAX_LOSS_PCT}%, dl≥${MIN_DL_MBIT}Mbps)"
  if [[ -n "$cur" ]]; then
    # Try to estimate current metrics too
    local cur_rtt cur_loss cur_dl cur_score
    read -r cur_rtt cur_loss < <(probe_rtt_loss "$cur")
    cur_dl="$(probe_throughput_mbit "$cur")"
    cur_score="$(score_line "$cur_rtt" "$cur_loss" "$cur_dl")"
    log "Current tunnel: ${cur}"
    log "  current metrics: avg=$(fmt_ms "$cur_rtt") loss=${cur_loss}% dl=${cur_dl}Mbps score=${cur_score}"
  fi

  # Evaluate candidates
  for c in "${CANDIDATES[@]}"; do
    # Only consider if interface/config exists in system
    if ! wg show | grep -q "interface: $c" && [[ ! -f "/etc/wireguard/${c}.conf" ]]; then
      continue
    fi

    read -r r l < <(probe_rtt_loss "$c")
    log "  ${c} ping: avg=$(fmt_ms "$r") loss=${l}%"
    log "  ${c} throughput test: up…"
    d="$(probe_throughput_mbit "$c")"
    log "  ${c} throughput: dl=${d}Mbps"
    s="$(score_line "$r" "$l" "$d")"
    log "  ${c} score=${s}"

    rtt_map["$c"]="$r"; loss_map["$c"]="$l"; dl_map["$c"]="$d"; score_map["$c"]="$s"
  done

  # Choose best that passes streaming thresholds
  best=""
  best_score=99999
  for c in "${!score_map[@]}"; do
    r="${rtt_map[$c]}"; l="${loss_map[$c]}"; d="${dl_map[$c]}"; s="${score_map[$c]}"
    # Must meet thresholds
    if (( r <= MAX_RTT_MS )) && (( ${l%.*} <= MAX_LOSS_PCT )) && (( d >= MIN_DL_MBIT )); then
      if (( s < best_score )); then best="$c"; best_score="$s"; fi
    fi
  done

  # If none passed thresholds, fall back to highest throughput
  if [[ -z "$best" ]]; then
    local best_dl=-1
    for c in "${!dl_map[@]}"; do
      d="${dl_map[$c]}"
      if (( d > best_dl )); then best="$c"; best_dl="$d"; fi
    done
  fi

  if [[ -z "$best" ]]; then
    log "No viable interfaces found; aborting."
    exit 0
  fi

  log "Connecting to best: ${best}  (avg=$(fmt_ms "${rtt_map[$best]}") loss=${loss_map[$best]}% dl=${dl_map[$best]}Mbps score=${score_map[$best]})"
# --- Toast block ---
best_line=$(grep "Connecting to best:" /var/log/wg-autoswitch.log | tail -n1); 
cc=$(echo "$best_line" | grep -oP "(?<=Connecting to best: )[a-z]{2}"); 
dl=$(echo "$best_line" | grep -oP "dl=\K[0-9.]+"); 
sc=$(echo "$best_line" | grep -oP "score=\K[0-9]+"); 
if [ -n "$cc" ] && [ -n "$dl" ] && [ -n "$sc" ] && [ "$dl" != "0" ]; then 
  pct=$(( (20000 - sc) * 100 / 20000 )); 
  dl_int=${dl%.*}; 
  toast_vpn_once "$cc" "$pct" "$dl_int"; 
fi 
# --- end toast block ---
  toast_vpn_once "${best_name^^}" "${score_pct}" "${dl_mbps}"

  # Switch if necessary
  if [[ "$cur" != "$best" ]]; then
    switch_to "$best" || true
  fi

  # Show a brief wg summary for the chosen iface
  if wg show "$best" >/dev/null 2>&1; then
    wg show "$best" | sed -E 's/^/    /' | while IFS= read -r line; do echo "$line"; done
  fi
}

main "$@"
