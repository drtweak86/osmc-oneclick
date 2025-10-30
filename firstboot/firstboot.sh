#!/usr/bin/env bash
# ---------------------------------------------
# OneClick XBian — firstboot.sh (Pi 4, 64-bit)
# Runs once on the very first boot, then disables itself.
# - Waits for Kodi + network + DNS
# - Ensures SSH + base tools
# - Clones/updates your oneclick repo and runs install.sh
# - Hardens WireGuard, installs daily health timer
# - Disables firstboot service, cleans up, reboots
# ---------------------------------------------
set -euo pipefail

STAMP="/var/lib/oneclick/firstboot.done"
LOG="/var/log/firstboot.log"
REPO_URL="https://github.com/drtweak86/osmc-oneclick.git"
REPO_DIR="/opt/osmc-oneclick"

# --- logging / toast helpers ---
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

ts()   { date "+%F %T"; }
log()  { echo "[firstboot $(ts)] $*"; }
toast(){
  # show notification in Kodi if possible (best-effort)
  if command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(OneClick,$*,7000)" >/dev/null 2>&1 || true
  elif command -v xbmc-send >/dev/null 2>&1; then
    xbmc-send --action="Notification(OneClick,$*,7000)" >/dev/null 2>&1 || true
  fi
}

# --- tiny utils ---
has_ip(){ ip -o -4 addr show "$1" 2>/dev/null | grep -q ' inet '; }

wait_for_kodi(){
  log "Waiting for Kodi service (up to 90s)…"
  for _ in $(seq 1 30); do
    systemctl is-active --quiet mediacenter && return 0 || true
    systemctl is-active --quiet kodi         && return 0 || true
    systemctl is-active --quiet xbmc         && return 0 || true
    sleep 3
  done
  log "Kodi did not report active; continuing anyway."
  return 0
}

wait_for_net(){
  log "Waiting for network (up to 120s)…"
  toast "Waiting for network…"
  for _ in $(seq 1 120); do
    # default route present + an IP on either eth0 or wlan0
    if ip route | grep -q '^default ' && { has_ip eth0 || has_ip wlan0; }; then
      local ip_now
      ip_now="$(hostname -I 2>/dev/null | awk '{print $1}')"
      log "Network up (IP: ${ip_now:-unknown})"
      toast "Network ready (IP ${ip_now:-unknown})"
      return 0
    fi
    sleep 1
  done
  log "No network detected; continuing (some steps may fail)."
  toast "No network detected; continuing"
}

wait_for_dns(){
  log "Checking DNS…"
  for _ in $(seq 1 30); do
    getent hosts github.com >/dev/null 2>&1 && { log "DNS OK"; toast "DNS OK"; return 0; }
    sleep 2
  done
  if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then
    log "DNS slow but internet is reachable."
    toast "DNS slow, internet reachable"
  else
    log "Internet not reachable; continuing anyway."
    toast "No internet; continuing"
  fi
}

ensure_ssh(){
  if systemctl list-unit-files | grep -q '^ssh\.service'; then
    systemctl enable --now ssh || true
    log "OpenSSH enabled"
  elif systemctl list-unit-files | grep -q '^dropbear\.service'; then
    systemctl enable --now dropbear || true
    log "Dropbear enabled"
  else
    log "No SSH service found (unexpected on XBian)."
  fi
  toast "SSH ensured"
}

ensure_prereq(){
  log "Installing prerequisites (git, curl, ca-certificates, unzip)…"
  # XBian uses APT; keep it quiet but resilient
  DEBIAN_FRONTEND=noninteractive apt-get update -y || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git curl ca-certificates unzip || true
}

harden_vpn(){
  # Lock down any preloaded WireGuard configs if present
  if [ -d /etc/wireguard ]; then
    chown -R root:root /etc/wireguard || true
    find /etc/wireguard -maxdepth 1 -type f -name '*.conf' -exec chmod 600 {} \; || true
    log "WireGuard permissions hardened."
  fi
}

install_status_timer(){
  # Expect these to be present after repo clone; best-effort copy
  if [ -f "$REPO_DIR/scripts/oneclick-status.sh" ]; then
    install -m 0755 "$REPO_DIR/scripts/oneclick-status.sh" /usr/local/bin/oneclick-status || true
  fi
  if [ -f "$REPO_DIR/systemd/oneclick-status.service" ]; then
    install -m 0644 "$REPO_DIR/systemd/oneclick-status.service" /etc/systemd/system/oneclick-status.service || true
  fi
  if [ -f "$REPO_DIR/systemd/oneclick-status.timer" ]; then
    install -m 0644 "$REPO_DIR/systemd/oneclick-status.timer" /etc/systemd/system/oneclick-status.timer || true
  fi
  systemctl daemon-reload || true
  systemctl enable --now oneclick-status.timer || true
  log "Daily status timer installed."
}

clone_or_update_repo(){
  toast "Fetching installer…"
  if [ -d "$REPO_DIR/.git" ]; then
    log "Updating existing repo in $REPO_DIR"
    git -C "$REPO_DIR" fetch --depth=1 origin main || true
    git -C "$REPO_DIR" reset --hard origin/main || true
  else
    log "Cloning $REPO_URL to $REPO_DIR"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --depth=1 "$REPO_URL" "$REPO_DIR"
  fi
}

run_installer(){
  toast "Running installer…"
  if [ -x "$REPO_DIR/install.sh" ]; then
    bash "$REPO_DIR/install.sh" || log "installer returned non-zero (check /var/log/osmc-oneclick-install.log)"
  else
    log "install.sh not found or not executable at $REPO_DIR/install.sh"
  fi
}

self_disable_and_reboot(){
  # Disable our systemd service so we don’t run again
  if systemctl list-unit-files | grep -q '^oneclick-firstboot\.service'; then
    systemctl disable oneclick-firstboot.service || true
  fi
  # Create a stamp for extra safety
  mkdir -p "$(dirname "$STAMP")"
  echo "done $(ts)" > "$STAMP"
  sync

  toast "First boot complete — rebooting"
  log  "First boot complete — rebooting"
  sleep 2
  reboot
}

main(){
  log "===== OneClick first boot start ====="
  toast "OneClick first boot starting…"

  # If we already ran, do nothing
  if [ -f "$STAMP" ]; then
    log "Stamp found ($STAMP) — exiting."
    exit 0
  fi

  wait_for_kodi
  wait_for_net
  wait_for_dns
  ensure_ssh
  ensure_prereq
  clone_or_update_repo

  # Optional add-ons baked in the repo:
  # - lock down VPN secrets if present
  harden_vpn
  # - install health status tool + timer
  install_status_timer

  # Hand off to your main installer
  run_installer

  # Clean up and reboot
  # (leave the script on /boot for debugging; safe to delete later)
  self_disable_and_reboot
}

main "$@"
