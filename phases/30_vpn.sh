#!/usr/bin/env bash
# phases/30_vpn.sh — XBian-safe WireGuard setup + autostart

set -euo pipefail

log(){ echo -e "[oneclick][30_vpn] $*"; }
warn(){ echo -e "[oneclick][WARN] $*" >&2; }
has(){ command -v "$1" >/dev/null 2>&1; }

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

log "Installing WireGuard and DNS helper (resolvconf → openresolv fallback)…"
apt-get update -y || true
if ! apt-get install -y --no-install-recommends wireguard resolvconf ; then
  warn "resolvconf not available — falling back to openresolv"
  apt-get install -y --no-install-recommends wireguard openresolv || true
fi

# --- Pull your private VPN configs as 'xbian' (SSH key expected in ~xbian/.ssh) ---
REPO_VPN="${REPO_VPN:-git@github.com:drtweak86/osmc-vpn-configs.git}"
DEST_VPN="${DEST_VPN:-/opt/osmc-vpn-configs}"

mkdir -p "$DEST_VPN"
chown -R xbian:xbian "$(dirname "$DEST_VPN")" || true

if [ -d "$DEST_VPN/.git" ]; then
  log "Updating VPN repo in $DEST_VPN"
  sudo -u xbian -H git -C "$DEST_VPN" fetch --depth=1 origin main || warn "git fetch failed"
  sudo -u xbian -H git -C "$DEST_VPN" reset --hard origin/main    || warn "git reset failed"
else
  log "Cloning VPN repo into $DEST_VPN"
  sudo -u xbian -H git clone --depth=1 "$REPO_VPN" "$DEST_VPN" || warn "git clone failed (check SSH key & repo access)"
fi

# --- Install WireGuard configs into /etc/wireguard ---
log "Placing configs into /etc/wireguard"
mkdir -p /etc/wireguard
shopt -s nullglob
confs=( "$DEST_VPN"/*.conf )

if [ ${#confs[@]} -eq 0 ]; then
  warn "No .conf files found in $DEST_VPN — skipping install and autostart"
  exit 0
fi

cp -f "${confs[@]}" /etc/wireguard/
chmod 600 /etc/wireguard/*.conf
chown root:root /etc/wireguard/*.conf
log "Installed configs:"
ls -1 /etc/wireguard/*.conf || true

# --- Choose first tunnel for autostart (override with FIRST_WG env if you want)
FIRST_WG="${FIRST_WG:-$(basename "$(ls /etc/wireguard/*.conf | head -n1)" .conf)}"
[ -n "${FIRST_WG:-}" ] || { warn "No WG name resolved for autostart"; exit 0; }

log "Autostarting WireGuard: ${FIRST_WG}"

if has systemctl; then
  # Systemd path
  if systemctl enable --now "wg-quick@${FIRST_WG}"; then
    log "wg-quick@${FIRST_WG} enabled and started (systemd)"
  else
    warn "wg-quick@${FIRST_WG} failed to start — attempting manual up"
    wg-quick up "${FIRST_WG}" || warn "wg-quick up ${FIRST_WG} failed"
  fi
else
  # Non-systemd (XBian/legacy) — ensure /etc/rc.local exists and is executable
  RC=/etc/rc.local
  if [ ! -f "$RC" ]; then
    cat >"$RC"<<'RCEOF'
#!/bin/sh -e
# rc.local - user commands run at end of multi-user boot
exit 0
RCEOF
    chmod +x "$RC"
  fi
  # Idempotently insert wg-quick up before exit 0
  if ! grep -q "wg-quick up ${FIRST_WG}" "$RC"; then
    log "Adding wg-quick up ${FIRST_WG} to $RC"
    sed -i "\#^exit 0#i /usr/bin/wg-quick up ${FIRST_WG} || true" "$RC"
  fi
  # Start now in current session too
  if wg-quick up "${FIRST_WG}"; then
    log "wg-quick up ${FIRST_WG} started (non-systemd)"
  else
    warn "wg-quick up ${FIRST_WG} failed — check config/DNS"
  fi
fi

# --- DNS registration heads-up ---
if has resolvconf; then
  log "resolvconf present — wg-quick will register tunnel DNS automatically"
else
  warn "resolvconf missing — DNS may not switch on connect (using openresolv)"
fi

log "VPN phase complete."
