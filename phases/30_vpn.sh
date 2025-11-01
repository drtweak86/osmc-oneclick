#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
set -euo pipefail

log(){ echo -e "[oneclick][30_vpn] $*"; }
warn(){ echo -e "[oneclick][WARN] $*" >&2; }

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

log "Installing WireGuard and DNS helper (resolvconf/openresolv fallback)…"
apt-get update -y || true
if ! apt-get install -y --no-install-recommends wireguard resolvconf ; then
  warn "resolvconf not available — falling back to openresolv"
  apt-get install -y --no-install-recommends wireguard openresolv
fi

# --- Pull your private VPN configs as 'osmc' (SSH key expected in ~osmc/.ssh) ---
REPO_VPN="git@github.com:drtweak86/osmc-vpn-configs.git"
DEST_VPN="/opt/osmc-vpn-configs"

mkdir -p "$(dirname "$DEST_VPN")"
chown -R osmc:osmc "$(dirname "$DEST_VPN")"

if [ -d "$DEST_VPN/.git" ]; then
  log "Updating VPN repo in $DEST_VPN"
  sudo -u osmc -H git -C "$DEST_VPN" fetch --depth=1 origin main || warn "git fetch failed"
  sudo -u osmc -H git -C "$DEST_VPN" reset --hard origin/main || warn "git reset failed"
else
  log "Cloning VPN repo into $DEST_VPN"
  sudo -u osmc -H git clone --depth=1 "$REPO_VPN" "$DEST_VPN" || warn "git clone failed (check SSH key & repo access)"
fi

# --- Install WireGuard configs into /etc/wireguard ---
log "Placing configs into /etc/wireguard"
mkdir -p /etc/wireguard
shopt -s nullglob
confs=("$DEST_VPN"/*.conf)

if [ ${#confs[@]} -eq 0 ]; then
  warn "No .conf files found in $DEST_VPN — skipping install and autostart"
else
  cp -f "${confs[@]}" /etc/wireguard/
  chmod 600 /etc/wireguard/*.conf
  chown root:root /etc/wireguard/*.conf
  log "Installed configs:"
  ls -1 /etc/wireguard/*.conf || true

  # --- Optional: auto-enable the first tunnel so it comes up on boot ---
  FIRST_WG="$(basename "$(ls /etc/wireguard/*.conf | head -n1)" .conf)"
  if [ -n "${FIRST_WG:-}" ]; then
    log "Enabling WireGuard service: wg-quick@${FIRST_WG}"
    if systemctl enable --now "wg-quick@${FIRST_WG}"; then
      log "wg-quick@${FIRST_WG} started successfully"
    else
      warn "wg-quick@${FIRST_WG} failed to start — check config/DNS"
    fi
  fi
fi

# --- DNS registration heads-up ---
if command -v resolvconf >/dev/null 2>&1; then
  log "resolvconf present — wg-quick will register tunnel DNS automatically"
else
  warn "resolvconf missing — DNS may not switch on connect (using openresolv)"
fi

log "VPN phase complete."
