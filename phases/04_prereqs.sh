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
  log "rclone not found — installing…"
  ensure_latest_rclone || log "WARN: rclone install script failed (offline?)."
else
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p' | head -n1 || true)"
  if [ -z "${have_ver:-}" ] || { [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; }; then
    log "Upgrading rclone (${have_ver:-unknown} → >= $need_ver)…"
    ensure_latest_rclone || log "WARN: rclone upgrade failed (offline?)."
  else
    log "rclone $have_ver OK (>= $need_ver)"
  fi
fi

hash -r || true
log "Prereqs ready."
