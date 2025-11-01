#!/usr/bin/env bash
# phases/33_install_speedtest.sh — install /usr/local/sbin/if-speedtest (XBian-safe)
set -euo pipefail

log(){ echo "[oneclick][33_speedtest] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

BIN="/usr/local/sbin/if-speedtest"
TMP="$(mktemp)"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Ensure target dir exists
install -d -m 0755 "$(dirname "$BIN")"

# Best-effort deps (okay if offline)
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
  apt-get update -y || true
  apt-get install -y --no-install-recommends curl iputils-ping jq ca-certificates || true
fi

cat > "$TMP" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# if-speedtest: quick downlink Mbps test bound to a specific network interface
# Usage: if-speedtest -i <iface> [-b <bytes>] [-t <timeout>] [-j]
IFACE=""
BYTES=$((4*1024*1024))  # 4 MiB
TIMEOUT=6
JSON=0

while getopts ":i:b:t:j" opt; do
  case "$opt" in
    i) IFACE="$OPTARG" ;;
    b) BYTES="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    j) JSON=1 ;;
    *) ;;
  esac
done

if [[ -z "$IFACE" ]]; then
  echo "0"; exit 0
fi

command -v curl >/dev/null 2>&1 || { echo "0"; exit 0; }
command -v date >/dev/null 2>&1 || { echo "0"; exit 0; }

URLS=(
  "http://speed.hetzner.de/100MB.bin"
  "http://ipv4.download.thinkbroadband.com/100MB.zip"
  "http://speedtest.tele2.net/100MB.zip"
)

best_mbps=0
used_url=""

for url in "${URLS[@]}"; do
  start=$(date +%s%3N)
  if curl --interface "$IFACE" --silent --show-error \
          --max-time "$TIMEOUT" \
          --range 0-$((BYTES-1)) \
          -o /dev/null "$url" 2>/dev/null; then
    end=$(date +%s%3N)
    dur_ms=$((end - start))
    (( dur_ms < 1 )) && dur_ms=1
    bits_per_s=$(( BYTES * 8000 / dur_ms ))
    mbit=$(( bits_per_s / 1000000 ))
    if (( mbit > best_mbps )); then
      best_mbps="$mbit"
      used_url="$url"
    fi
  fi
done

echo "$best_mbps"

if (( JSON == 1 )); then
  {
    echo "{"
    echo "  \"iface\": \"${IFACE}\","
    echo "  \"bytes\": ${BYTES},"
    echo "  \"timeout\": ${TIMEOUT},"
    echo "  \"mbps\": ${best_mbps},"
    echo "  \"url\": \"${used_url}\""
    echo "}"
  } >&2
fi
SCRIPT

install -m 0755 "$TMP" "$BIN"
rm -f "$TMP"
log "Installed $BIN"
