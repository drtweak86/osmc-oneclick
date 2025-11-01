#!/usr/bin/env bash
# shellcheck disable=SC1091
# ------------------------------------------------------------
# Phase: 04_prereqs.sh
# Purpose: Install core runtime + developer packages, monitoring tools,
#          and ensure rclone is available (XBian-compatible).
# ------------------------------------------------------------

source /opt/osmc-oneclick/phases/31_helpers.sh 2>/dev/null || true
set -euo pipefail

# --- Logging helpers --------------------------------------------------------
log(){ echo "[oneclick][04_prereqs] $*"; }
type -t warn >/dev/null 2>&1 || warn(){ echo "[oneclick][WARN] $*" >&2; }

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# --- Retry helper -----------------------------------------------------------
retry() {
  local n=$1 s=$2; shift 2
  local i
  for i in $(seq 1 "$n"); do
    "$@" && return 0 || true
    sleep "$s"
  done
  return 1
}

# --- APT hardening (helps over unstable Wi-Fi) -------------------------------
APT_OPTS="-o Acquire::Retries=3 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15"

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
retry 2 5 apt-get $APT_OPTS update -y || true
retry 2 5 apt-get $APT_OPTS install -y --no-install-recommends "${PKGS[@]}" || true

# ---------------------------------------------------------------------------
# 📊  Optional monitoring / diagnostics (tiny but handy)
# ---------------------------------------------------------------------------
MON_PKGS=(htop iotop nload)
log "Installing monitoring tools: ${MON_PKGS[*]}"
retry 2 5 apt-get $APT_OPTS install -y --no-install-recommends "${MON_PKGS[@]}" || true

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
else
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p' | head -n1 || true)"
  if [ -z "${have_ver:-}" ] || { [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; }; then
    log "Upgrading rclone (${have_ver:-unknown} → >= $need_ver)…"
    ensure_latest_rclone || warn "rclone upgrade failed (offline?)."
  else
    log "rclone $have_ver OK (>= $need_ver)"
  fi
fi

hash -r || true
log "Prereqs ready."
