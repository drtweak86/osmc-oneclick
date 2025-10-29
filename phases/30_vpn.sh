#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "[oneclick][30_vpn] $*"; }

log "Installing WireGuard + DNS helper"
apt-get update
# Prefer resolvconf; fall back to openresolv if not available
if ! apt-get install -y --no-install-recommends wireguard resolvconf ; then
  apt-get install -y --no-install-recommends wireguard openresolv
fi

# Clone the PRIVATE VPN configs as 'osmc' (uses osmc's ~/.ssh keys)
REPO_VPN="git@github.com:drtweak86/osmc-vpn-configs.git"
DEST_VPN="/opt/osmc-vpn-configs"

mkdir -p "$(dirname "$DEST_VPN")"
chown osmc:osmc "$(dirname "$DEST_VPN")"

if [ -d "$DEST_VPN/.git" ]; then
  log "Updating VPN repo in $DEST_VPN"
  sudo -u osmc -H git -C "$DEST_VPN" fetch --depth=1 origin main
  sudo -u osmc -H git -C "$DEST_VPN" reset --hard origin/main
else
  log "Cloning VPN repo into $DEST_VPN"
  sudo -u osmc -H git clone --depth=1 "$REPO_VPN" "$DEST_VPN"
fi

# Install configs
log "Placing configs into /etc/wireguard"
mkdir -p /etc/wireguard
# Copy only *.conf if present
shopt -s nullglob
confs=("$DEST_VPN"/*.conf)
if [ ${#confs[@]} -eq 0 ]; then
  log "WARNING: No .conf files found in $DEST_VPN"
else
  cp -v "${confs[@]}" /etc/wireguard/
  chmod 600 /etc/wireguard/*.conf
  chown root:root /etc/wireguard/*.conf
  log "Installed configs:"
  ls -1 /etc/wireguard/*.conf || true
fi

# Tiny wg-quick tweak: some setups prefer resolvconf tag 'tun.NAME'
if command -v resolvconf >/dev/null 2>&1; then
  log "resolvconf present; wg-quick will register DNS for tunnels"
fi

log "VPN phase complete."
