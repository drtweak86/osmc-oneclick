#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[oneclick][04_prereqs] $*"; }

# unzip + certs
if ! command -v unzip >/dev/null 2>&1; then
  log "Installing unzip + ca-certificates"
  apt-get update -y || true
  apt-get install -y unzip ca-certificates || true
fi

ensure_latest_rclone() {
  curl -fsSL https://rclone.org/install.sh | bash
}

if ! command -v rclone >/dev/null 2>&1; then
  log "rclone not found — installing"
  ensure_latest_rclone
else
  need_ver="1.68"
  have_ver="$(rclone version 2>/dev/null | sed -n 's/^rclone v\([0-9.]\+\).*/\1/p')"
  if [ -z "${have_ver:-}" ] || [ "$(printf '%s\n' "$need_ver" "$have_ver" | sort -V | head -n1)" = "$have_ver" ] && [ "$have_ver" != "$need_ver" ]; then
    log "Upgrading rclone ($have_ver → >=$need_ver)"
    ensure_latest_rclone
  else
    log "rclone $have_ver OK"
  fi
fi

log "Prereqs ready"
