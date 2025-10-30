#!/usr/bin/env bash
# phases/22_argon_one.sh
# Argon One Pi4 V2: install daemon + apply 3-step fan curve
set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

log "[argon] Setting up Argon One (Pi4 V2)"

# --- Detect Pi4 only ---
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null; then
  warn "[argon] Not a Pi 4 — skipping Argon setup"
  exit 0
fi

# --- Install Argon daemon if missing (official script is idempotent) ---
if ! systemctl list-unit-files | grep -q '^argononed\.service'; then
  log "[argon] Installing Argon One service"
  curl -fsSL https://download.argon40.com/argon1.sh | bash || {
    warn "[argon] Argon installer failed (possibly offline). Skipping."
    exit 0
  }
fi

# --- Default preset for media streaming (Balanced) ---
PRESET="${ARGON_PRESET:-balanced}"

make_curve() {
  case "$1" in
    performance)
      echo -e "50=35\n60=70\n70=100" ;;       # coolest, louder
    balanced)
      echo -e "55=25\n65=55\n75=100" ;;       # recommended for media
    quiet|silent)
      echo -e "60=20\n70=45\n80=100" ;;       # quietest, warmer
    *)
      echo -e "55=25\n65=55\n75=100" ;;       # fallback
  esac
}

# --- Apply the chosen curve to Argon config(s) ---
CONF1="/etc/argononed.conf"
CONF2="/etc/argonone.conf"
CURVE="$(make_curve "$PRESET")"

log "[argon] Applying '$PRESET' fan curve:"
printf '%s\n' "$CURVE" | sudo tee "$CONF1" >/dev/null
printf '%s\n' "$CURVE" | sudo tee "$CONF2" >/dev/null || true

# --- Enable + restart the service ---
sudo systemctl enable --now argononed.service || true
sudo systemctl restart argononed.service || true

log "[argon] Argon One V2 setup complete — preset: $PRESET"
