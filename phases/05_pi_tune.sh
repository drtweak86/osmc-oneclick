#!/usr/bin/env bash
set -euo pipefail
say(){ echo "[oneclick][05_pi_tune] $*"; }

CFG_DIR="/boot/config.txt.d"
CFG_FILE="$CFG_DIR/99-media-tune.conf"

mkdir -p "$CFG_DIR"
cat >"$CFG_FILE"<<'EOF'
# Raspberry Pi 4B Media Optimisation
arm_freq=2000
gpu_freq=750
over_voltage=6
gpu_mem=320
dtoverlay=vc4-kms-v3d,cma-512
EOF

# Make sure main config includes the .d directory
if ! grep -q 'config.txt.d' /boot/config.txt 2>/dev/null; then
  say "Linking /boot/config.txt.d into /boot/config.txt"
  printf '\n# Include per-file configs\n[all]\ninclude config.txt.d/*.conf\n' >> /boot/config.txt
fi

say "Media tuning staged. Reboot required to take effect."
