#!/usr/bin/env bash
# phases/20_optimize.sh
# System optimisations for streaming: entropy, local DNS cache, TCP tuning.
# XBian/OSMC friendly (no hard dependency on systemd).

set -euo pipefail

# Optional helpers (script runs fine without them)
[ -f /opt/osmc-oneclick/phases/31_helpers.sh ] && . /opt/osmc-oneclick/phases/31_helpers.sh || true
log(){ echo "[oneclick][20_optimize] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

has() { command -v "$1" >/dev/null 2>&1; }
enable_service() {
  # $1 = service name (without .service)
  if has systemctl; then
    systemctl enable --now "$1" 2>/dev/null || systemctl restart "$1" || true
  elif has update-rc.d; then
    update-rc.d "$1" defaults 2>/dev/null || true
    if has service; then service "$1" start || service "$1" restart || true; fi
  elif has service; then
    service "$1" start || service "$1" restart || true
  fi
}

# -------- Entropy + DNS cache ------------------------------------------------
if has apt-get; then
  log "Installing rng-tools + Unbound (DNS cache)…"
  apt-get update -y || true

  # Prefer rng-tools-debian if present, else rng-tools
  if apt-cache show rng-tools-debian >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends rng-tools-debian || true
  else
    apt-get install -y --no-install-recommends rng-tools || true
  fi

  apt-get install -y --no-install-recommends unbound || true

  # Minimal caching resolver config (only if none exists)
  if [ ! -s /etc/unbound/unbound.conf ] && [ -d /etc/unbound ]; then
    cat >/etc/unbound/unbound.conf <<'CONF'
server:
  verbosity: 0
  interface: 127.0.0.1
  port: 53
  do-ip4: yes
  do-ip6: no
  do-udp: yes
  do-tcp: yes
  prefetch: yes
  cache-min-ttl: 300
  cache-max-ttl: 86400
  hide-identity: yes
  hide-version: yes

  # Hardening
  harden-glue: yes
  harden-dnssec-stripped: yes
  harden-referral-path: yes

  # Memory caps (lightweight)
  msg-cache-size: 32m
  rrset-cache-size: 64m

forward-zone:
  name: "."
  forward-tls-upstream: no
  forward-addr: 1.1.1.1
  forward-addr: 1.0.0.1
CONF
  fi

  # Start & enable unbound across boots
  enable_service unbound

else
  warn "apt-get not available; skipping package installs."
fi

# -------- TCP/queue tuning ---------------------------------------------------
SYSCTL_FILE="/etc/sysctl.d/99-osmc-oneclick.conf"

# Try BBR, fall back to cubic
TCP_CC="bbr"
if ! modprobe tcp_bbr 2>/dev/null; then
  warn "tcp_bbr not available; falling back to cubic"
  TCP_CC="cubic"
fi

# Prefer fq qdisc if kernel supports it
QDISC="fq"
if ! sysctl net.core.default_qdisc 2>/dev/null | grep -q .; then
  # Older sysctl may lack this; will still write it for next boot
  true
fi

cat >"$SYSCTL_FILE"<<EOF
# --- OneClick streaming sysctl ---
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 4096 87380 2097152
net.ipv4.tcp_wmem = 4096 65536 2097152
net.ipv4.tcp_congestion_control = ${TCP_CC}
net.core.default_qdisc = ${QDISC}
EOF

# Apply immediately, key-by-key (works even without systemd)
apply_sysctl() {
  local k v
  while read -r k _ v; do
    [ -n "${k:-}" ] && [ -n "${v:-}" ] && sysctl -w "$k=$v" >/dev/null 2>&1 || true
  done < <(grep -Ev '^\s*#|^\s*$' "$SYSCTL_FILE")
}
apply_sysctl

log "Optimisation complete (cc=${TCP_CC}, qdisc=${QDISC}). Reboot not required, but recommended."
