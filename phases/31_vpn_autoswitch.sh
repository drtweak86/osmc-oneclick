#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
set -euo pipefail

# =========================
# Config / defaults
# =========================
[ -f /etc/default/wg-autoswitch ] && . /etc/default/wg-autoswitch

: "${MIN_DL_MBIT:=12}"
: "${MAX_RTT_MS:=80}"
: "${MAX_LOSS_PCT:=2}"
: "${TEST_BYTES:=$((4*1024*1024))}"
: "${PING_TARGET:=1.1.1.1}"
: "${LOG_FILE:=/var/log/wg-autoswitch.log}"
: "${ICON:=🦈}"

CANDIDATES=( de-ber nl-ams uk-lon uk-man us-nyc )
WG_SWITCH_BIN="/usr/local/sbin/wg-switch"
IF_SPEEDTEST="/usr/local/sbin/if-speedtest"

# Helpers (toast + country/quality)
. /opt/xbian-oneclick/phases/31_helpers.sh

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
  local line="[oneclick][31_autoswitch] $*"
  echo -e "$line"
  { mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true; echo -e "$line"; } >>"$LOG_FILE" 2>/dev/null || true
}
log() {
  local msg="$*"
  if [[ "$msg" =~ ^Connecting\ to\ best:\ ([A-Za-z0-9_-]+)\  ]]; then
    local b="${BASH_REMATCH[1]}"
    msg="Connecting to best: ${b} $(flag "$b") ${ICON}${msg#Connecting to best: ${b}}"
  fi
  _log "$msg"
}

# =========================
# Probing functions
# =========================
probe_rtt_loss() {
  local iface="$1" line loss avg rtt
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
  local iface="$1"
  # Prefer external tester (supports multiple mirrors)
  if [[ -x "$IF_SPEEDTEST" ]]; then
    "$IF_SPEEDTEST" -i "$iface" -b "$TEST_BYTES"
    return 0
  fi
  # Fallback: single mirror range probe
  local url="http://speed.hetzner.de/100MB.bin"
  local bytes="$TEST_BYTES"
  local start end dur_ms bits_per_s mbit
  start=$(date +%s%3N)
  if ! curl --interface "$iface" --silent --show-error --max-time 6 \
            --range 0-$((bytes-1)) -o /dev/null "$url" 2>/dev/null; then
    echo "0"; return 0
  fi
  end=$(date +%s%3N)
  dur_ms=$((end - start))
  (( dur_ms < 1 )) && dur_ms=1
  bits_per_s=$(( bytes * 8000 / dur_ms ))
  mbit=$(( bits_per_s / 1000000 ))
  echo "$mbit"
}

score_line() {
  local rtt_ms="$1" loss_pct="$2" dl_mbit="$3"
  local loss_penalty=$(( ${loss_pct%.*} * 50 ))
  echo $(( 10000 - dl_mbit + rtt_ms + loss_penalty ))
}

current_iface() { wg show | awk '/interface:/{print $2; exit}'; }

switch_to() {
  local target="$1"
  if [[ -x "$WG_SWITCH_BIN" ]]; then
    "$WG_SWITCH_BIN" "$target"
  elif [[ -f "/etc/wireguard/${target}.conf" ]]; then
    local cur
    cur="$(current_iface || true)"
    [[ -n "$cur" && "$cur" != "$target" ]] && (wg-quick down "$cur" >/dev/null 2>&1 || true)
    wg-quick up "$target"
  else
    _log "WARN: No $WG_SWITCH_BIN and no /etc/wireguard/${target}.conf; cannot switch."
    return 1
  fi
}

# =========================
# Main
# =========================
main() {
  local cur best="" best_score=99999
  local -A rtt_map loss_map dl_map score_map

  cur="$(current_iface || true)"

  log "Starting VPN auto-switch check (rtt≤${MAX_RTT_MS}ms, loss≤${MAX_LOSS_PCT}%, dl≥${MIN_DL_MBIT}Mbps)"
  if [[ -n "$cur" ]]; then
    local cr cl cdl cs
    read -r cr cl < <(probe_rtt_loss "$cur")
    cdl="$(probe_throughput_mbit "$cur")"
    cs="$(score_line "$cr" "$cl" "$cdl")"
    log "Current tunnel: ${cur}"
    log "  current metrics: avg=$(fmt_ms "$cr") loss=${cl}% dl=${cdl}Mbps score=${cs}"
  fi

  # Evaluate candidates
  for c in "${CANDIDATES[@]}"; do
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

  # Pick best that meets thresholds
  for c in "${!score_map[@]}"; do
    r="${rtt_map[$c]}"; l="${loss_map[$c]}"; d="${dl_map[$c]}"; s="${score_map[$c]}"
    if (( r <= MAX_RTT_MS )) && (( ${l%.*} <= MAX_LOSS_PCT )) && (( d >= MIN_DL_MBIT )); then
      (( s < best_score )) && { best="$c"; best_score="$s"; }
    fi
  done

  # Fallback: highest throughput
  if [[ -z "$best" ]]; then
    local best_dl=-1
    for c in "${!dl_map[@]}"; do
      d="${dl_map[$c]}"
      (( d > best_dl )) && { best="$c"; best_dl="$d"; }
    done
  fi

  if [[ -z "$best" ]]; then
    log "No viable interfaces found; aborting."
    exit 0
  fi

  log "Connecting to best: ${best}  (avg=$(fmt_ms "${rtt_map[$best]}") loss=${loss_map[$best]}% dl=${dl_map[$best]}Mbps score=${score_map[$best]})"

  # Toast (single path)
  local cn sp qp
  cn="$(country_name_from_iface "$best")"
  sp="${dl_map[$best]}"
  qp="$(quality_pct_from_speed "$sp")"
  toast_vpn_once "$cn" "$qp" "$sp"

  # Switch if needed
  if [[ "$cur" != "$best" ]]; then
    switch_to "$best" || true
  fi

  # Brief wg summary
  if wg show "$best" >/dev/null 2>&1; then
    wg show "$best" | sed -E 's/^/    /'
  fi
}

main "$@"
