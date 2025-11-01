#!/usr/bin/env bash
# shellcheck disable=SC1091
source /opt/osmc-oneclick/phases/31_helpers.sh
# phases/22_argon_one.sh
# Argon One Pi4 V2: install daemon + apply 3-step fan curve (idempotent)

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

log "[argon] Setting up Argon One (Pi4 V2)"

# Only Pi 4
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null; then
  warn "[argon] Not a Pi 4 — skipping Argon setup"
  exit 0
fi

# Install Argon daemon if missing
if ! systemctl list-unit-files | grep -q '^argononed\.service'; then
  log "[argon] Installing Argon One service"
  if ! curl -fsSL https://download.argon40.com/argon1.sh | bash; then
    warn "[argon] Argon installer failed (possibly offline). Skipping."
    exit 0
  fi
fi

# Choose preset via env ARGON_PRESET: performance|balanced|quiet
PRESET="${ARGON_PRESET:-balanced}"

make_curve() {
  case "$1" in
    performance) echo -e "50=35\n60=70\n70=100" ;;  # coolest, louder
    balanced)    echo -e "55=25\n65=55\n75=100" ;;  # good for media
    quiet|silent)echo -e "60=20\n70=45\n80=100" ;;  # quietest, warmer
    *)           echo -e "55=25\n65=55\n75=100" ;;
  esac
}

CURVE="$(make_curve "$PRESET")"
for conf in /etc/argononed.conf /etc/argonone.conf; do
  printf '%s\n' "$CURVE" | tee "$conf" >/dev/null || true
done

systemctl enable --now argononed.service || true
systemctl restart argononed.service || true

log "[argon] Argon One V2 setup complete — preset: $PRESET"
