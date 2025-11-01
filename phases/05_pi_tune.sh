#!/usr/bin/env bash
# phases/05_pi_tune.sh
# Safe Raspberry Pi 4B media tuning with boot-loop guards (XBian/RPi OS)
# - No turbo (warranty-safe)
# - Only runs on Pi 4
# - Conservative clocks + GPU mem
# - Easy skip/rollback

set -euo pipefail
log(){ echo "[oneclick][05_pi_tune] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

# --- Quick escapes / model checks ---
# Create /boot/oneclick-skip to skip tuning (panic button)
[ -f /boot/oneclick-skip ] && { log "Skip flag present (/boot/oneclick-skip). Skipping."; exit 0; }

# Only Pi 4
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null; then
  log "Not a Raspberry Pi 4 — skipping Pi tune."
  exit 0
fi

# --- Where to write things ---
BOOT_CFG="/boot/config.txt"
[ -f /boot/firmware/config.txt ] && BOOT_CFG="/boot/firmware/config.txt"
CONF_DIR="$(dirname "$BOOT_CFG")/config.txt.d"
CONF_FILE="${CONF_DIR}/99-media-tune.conf"
BAK_FILE="${BOOT_CFG}.oneclick.bak"

# --- Safe defaults (warranty-friendly) ---
ARM_FREQ="${ARM_FREQ:-1800}"       # 1800 is safe on most Pi4Bs
GPU_FREQ="${GPU_FREQ:-600}"        # conservative GPU bump
OVER_VOLTAGE="${OVER_VOLTAGE:-2}"  # warranty-safe (no turbo fuse)
GPU_MEM="${GPU_MEM:-320}"          # enough for 4K skins/decoding
DTO="${DTO:-vc4-kms-v3d,cma-512}"  # modern KMS + bigger CMA

# Clamp values to sensible ranges
clamp() { local v=$1 lo=$2 hi=$3; [ "$v" -lt "$lo" ] && v=$lo; [ "$v" -gt "$hi" ] && v=$hi; echo "$v"; }
ARM_FREQ="$(clamp "$ARM_FREQ" 1500 2000)"
GPU_FREQ="$(clamp "$GPU_FREQ" 500 700)"
OVER_VOLTAGE="$(clamp "$OVER_VOLTAGE" -16 6)"
GPU_MEM="$(clamp "$GPU_MEM" 256 512)"

# --- Back up main config (once) ---
if [ ! -f "$BAK_FILE" ]; then
  cp -a "$BOOT_CFG" "$BAK_FILE" || true
  log "Backed up $(basename "$BOOT_CFG") -> $(basename "$BAK_FILE")"
fi

# --- Ensure include support and write our file ---
mkdir -p "$CONF_DIR"
cat >"$CONF_FILE"<<EOF
# --- OneClick: Raspberry Pi 4B Safe Media Optimisation ---
# Warranty-safe, conservative settings
force_turbo=0
arm_freq=${ARM_FREQ}
gpu_freq=${GPU_FREQ}
over_voltage=${OVER_VOLTAGE}
gpu_mem=${GPU_MEM}
dtoverlay=${DTO}
EOF
chmod 0644 "$CONF_FILE"

# Add include line if missing
if ! grep -Eq '^[[:space:]]*include[[:space:]]+config\.txt\.d/\*\.conf' "$BOOT_CFG"; then
  log "Linking $(basename "$CONF_DIR")/*.conf from $(basename "$BOOT_CFG")"
  printf '\n# Include per-file configs (OneClick)\n[all]\ninclude config.txt.d/*.conf\n' >> "$BOOT_CFG"
fi

sync
log "Safe media tuning staged: $CONF_FILE"
log "Settings: arm_freq=${ARM_FREQ} gpu_freq=${GPU_FREQ} over_voltage=${OVER_VOLTAGE} gpu_mem=${GPU_MEM} dtoverlay=${DTO}"

# --- Post-boot verification helper (optional) ---
# After reboot, you can run:
#   vcgencmd measure_clock arm
#   vcgencmd measure_volts
#   sysctl net.ipv4.tcp_congestion_control
exit 0
