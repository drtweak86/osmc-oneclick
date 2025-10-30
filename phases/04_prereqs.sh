#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[oneclick][04_prereqs] $*"; }
export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

retry() { local n=$1 s=$2; shift 2; for i in $(seq 1 "$n"); do "$@" && return 0 || true; sleep "$s"; done; return 1; }

# unzip, zip, certs
if ! command -v unzip >/dev/null 2>&1 || ! command -v zip >/dev/null 2>&1; then
  log "Installing unzip, zip, ca-certificates..."
  retry 2 5 apt-get update -y || true
  retry 2 5 apt-get install -y unzip zip ca-certificates || true
fi

ensure_latest_rclone() { curl -fsSL https://rclone.org/install.sh | bash; }

need_ver="1.68"
if ! command -v rclone >/dev/null 2>&1; then
  log "rclone not found — installing…"
  ensure_latest_rclone
else
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p' | head -n1 || true)"
  if [ -z "${have_ver:-}" ] || { [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; }; then
    log "Upgrading rclone (${have_ver:-unknown} → >= $need_ver)…"
    ensure_latest_rclone
  else
    log "rclone $have_ver OK (>= $need_ver)"
  fi
fi

log "Prereqs ready."
