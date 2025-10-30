#!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/firstboot.log
exec > >(tee -a "$LOG") 2>&1

log()   { echo "[firstboot] $(date '+%F %T') $*"; }
toast() { command -v kodi-send >/dev/null 2>&1 && kodi-send --action="Notification(First Boot,$*,7000)" >/dev/null 2>&1 || true; }

has_ip() { ip -4 addr show "$1" 2>/dev/null | grep -q "inet "; }

wait_for_kodi() {
  for i in $(seq 1 30); do
    systemctl is-active --quiet xbmc  && return 0
    systemctl is-active --quiet kodi  && return 0
    systemctl is-active --quiet mediacenter && return 0
    sleep 3
  done
  return 0
}

wait_for_net() {
  log "Waiting for network…"; toast "Starting… waiting for network"
  for i in $(seq 1 60); do
    if has_ip eth0 || has_ip wlan0; then ip route | grep -q '^default ' && break; fi
    sleep 2
  done
  IP_NOW="$(hostname -I 2>/dev/null | awk '{print $1}')"
  log "Network up (IP: ${IP_NOW:-unknown})"; toast "Network ready (IP: ${IP_NOW:-unknown})"
}

wait_for_dns() {
  log "Waiting for DNS…"
  for i in $(seq 1 30); do
    getent hosts github.com >/dev/null 2>&1 && { log "DNS OK"; toast "DNS OK"; return 0; }
    sleep 2
  done
  if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
    log "DNS slow but internet reachable"; toast "DNS slow but reachable"
  else
    log "No internet; proceeding anyway"; toast "No internet detected (proceeding)"
  fi
}

ensure_ssh() {
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl enable --now ssh || true
  elif systemctl list-unit-files | grep -q '^dropbear\.service'; then
    systemctl enable --now dropbear || true
  fi
  log "SSH ensured"; toast "SSH enabled"
}

ensure_prereq() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || true
  apt-get install -y --no-install-recommends git curl ca-certificates || true
}

REPO="https://github.com/drtweak86/osmc-oneclick.git"
DEST="/opt/osmc-oneclick"

log "First boot starting…"
wait_for_kodi || true
wait_for_net
wait_for_dns
ensure_ssh
ensure_prereq

toast "Fetching installer…"
log "Cloning/updating $REPO"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --depth=1 origin main || true
  git -C "$DEST" reset --hard origin/main || true
else
  mkdir -p "$(dirname "$DEST")"
  git clone --depth=1 "$REPO" "$DEST"
fi

toast "Running installer…"
log "Running $DEST/install.sh"
bash "$DEST/install.sh" || log "Installer returned non-zero (see /var/log/osmc-oneclick-install.log)"

toast "First boot complete. Rebooting…"
log "Disabling service & cleaning up"
systemctl disable oneclick-firstboot.service || true
rm -f /boot/firstboot.sh || true
sync; sleep 2; reboot
