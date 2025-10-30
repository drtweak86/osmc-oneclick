#!/usr/bin/env bash
set -euo pipefail
say(){ echo "[oneclick][06_argon] $*"; }

# Preset: balanced by default; options: balanced|quiet|performance
PRESET="${ARGON_PRESET:-balanced}"

case "$PRESET" in
  quiet)        map="55=25\n65=60\n75=100" ;;
  performance)  map="45=50\n55=75\n65=100" ;;
  *)            map="50=25\n60=60\n70=100" ;; # balanced
esac

CONF="/etc/argononed.conf"
if [ -f /usr/bin/argonone-config ] || [ -f /usr/bin/argononed.py ] || [ -f /usr/sbin/argononed ]; then
  say "Writing Argon One fan map ($PRESET)"
  printf "%b\n" "$map" > "$CONF"
  systemctl enable argononed.service 2>/dev/null || true
  systemctl restart argononed.service 2>/dev/null || true
else
  say "Argon One daemon not detected; skipping (safe)."
fi
