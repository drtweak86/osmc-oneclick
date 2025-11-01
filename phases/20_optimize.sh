#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
# phases/20_optimize.sh
# System optimisations for streaming: rng, DNS cache, TCP tuning with BBR fallback.
# Does NOT touch /boot or GPU/OC (handled by 05_pi_tune.sh).

set -euo pipefail
log(){ echo "[oneclick][20_optimize] $*"; }
warn(){ echo "[oneclick][WARN] $*">&2; }

export DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}

# -------- Small utilities ----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  log "Installing rng-tools (entropy) and unbound (local DNS cache)…"
  apt-get update -y || true
  apt-get install -y --no-install-recommends rng-tools unbound || true
  systemctl enable --now unbound || true
else
  warn "apt-get not available; skipping package installs."
fi

# -------- TCP/queue tuning ---------------------------------------------------
SYSCTL_FILE="/etc/sysctl.d/99-osmc-oneclick.conf"

# Try to enable BBR; if not available, fall back to 'cubic'
TCP_CC="bbr"
if ! modprobe tcp_bbr 2>/dev/null; then
  warn "tcp_bbr module not available; falling back to cubic"
  TCP_CC="cubic"
fi

cat >"$SYSCTL_FILE"<<EOS
# --- OneClick streaming sysctl ---
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 4096 87380 2097152
net.ipv4.tcp_wmem = 4096 65536 2097152
net.ipv4.tcp_congestion_control = ${TCP_CC}
EOS

# Apply immediately (best effort)
if sysctl --system; then
  log "Applied sysctl settings (tcp_congestion_control=${TCP_CC})."
else
  warn "sysctl --system failed; values will apply on next boot."
fi

# -------- Final notes --------------------------------------------------------
log "Optimisation complete. No /boot changes here (handled by 05_pi_tune.sh)."
