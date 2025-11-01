#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
set -euo pipefail
log(){ echo "[oneclick][04_prereqs] $*"; }
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

retry() { local n=$1 s=$2; shift 2; local i; for i in $(seq 1 "$n"); do "$@" && return 0 || true; sleep "$s"; done; return 1; }

# ---------------------------------------------------------------------------
# 🧩  Core runtime + developer packages
# ---------------------------------------------------------------------------
PKGS=(
  curl wget git jq zip unzip ca-certificates
  rng-tools rsync dnsutils net-tools
  python3 python3-pip ffmpeg
  nano vim tmux build-essential file lsof strace ncdu
)

log "Installing essential + developer packages: ${PKGS[*]}"
retry 2 5 apt-get update -y || true
retry 2 5 apt-get install -y --no-install-recommends "${PKGS[@]}" || true

# ---------------------------------------------------------------------------
# 📊  Optional monitoring / diagnostics (tiny but handy)
# ---------------------------------------------------------------------------
MON_PKGS=(htop iotop nload)
log "Installing monitoring tools: ${MON_PKGS[*]}"
retry 2 5 apt-get install -y --no-install-recommends "${MON_PKGS[@]}" || true

# ---------------------------------------------------------------------------
# 🧠  Ensure rclone is up to date
# ---------------------------------------------------------------------------
ensure_latest_rclone() {
  retry 2 5 bash -c 'curl -fsSL https://rclone.org/install.sh | bash'
}

need_ver="1.68"
if ! command -v rclone >/dev/null 2>&1; then
  log "Installing latest rclone…"
  ensure_latest_rclone
  command -v rclone >/dev/null 2>&1 && log "rclone installed OK" || warn "rclone missing after install"
fi
hash -r || true
log "Prereqs ready."
