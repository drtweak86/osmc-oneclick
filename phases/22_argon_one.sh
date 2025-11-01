#!/usr/bin/env bash
# phases/22_argon_one.sh
# Argon One Pi4 V2: install daemon + apply 3-step fan curve (idempotent, XBian/OSMC safe)

set -euo pipefail

# Optional helpers
[ -f /opt/osmc-oneclick/phases/31_helpers.sh ] && . /opt/osmc-oneclick/phases/31_helpers.sh || true
log(){ echo "[oneclick][argon] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }
svc_enable_now() {
  # $1 = service name without .service
  local S="$1"
  if has systemctl; then
    systemctl enable --now "$S" 2>/dev/null || systemctl restart "$S" || true
  elif has update-rc.d; then
    update-rc.d "$S" defaults 2>/dev/null || true
    if has service; then service "$S" start || service "$S" restart || true; fi
  elif has service; then
    service "$S" start || service "$S" restart || true
  fi
}

log "Setting up Argon One (Pi4 V2)"

# Only Pi 4
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null; then
  warn "Not a Pi 4 — skipping Argon setup"
  exit 0
fi

# Install Argon daemon if missing
ARGON_SVC="argononed"
if ! (has systemctl && systemctl list-unit-files 2>/dev/null | grep -q "^${ARGON_SVC}\.service") \
   && ! [ -f "/etc/init.d/${ARGON_SVC}" ]; then
  log "Argon service not found — installing"
  if ! has curl; then
    warn "curl not found; cannot fetch Argon installer"
    exit 0
  fi
  if ! bash -c 'curl -fsSL https://download.argon40.com/argon1.sh | bash'; then
    warn "Argon installer failed (offline or repo issue). Skipping."
    exit 0
  fi
else
  log "Argon service already present"
fi

# Choose preset via env ARGON_PRESET: performance|balanced|quiet
PRESET="${ARGON_PRESET:-balanced}"
case "$PRESET" in
  performance) CURVE=$'50=35\n60=70\n70=100' ;;   # coolest, louder
  balanced)    CURVE=$'55=25\n65=55\n75=100' ;;   # good for media
  quiet|silent)CURVE=$'60=20\n70=45\n80=100' ;;   # quietest, warmer
  *)           CURVE=$'55=25\n65=55\n75=100' ;;
esac

# Write curve to whichever config the daemon uses
for conf in /etc/argononed.conf /etc/argonone.conf; do
  printf '%s\n' "$CURVE" | tee "$conf" >/dev/null || true
done

# Enable/start service (systemd or SysV)
svc_enable_now "${ARGON_SVC}"

log "Argon One V2 setup complete — preset: ${PRESET}"
