#!/usr/bin/env bash
# phases/05_pi_tune.sh
# Raspberry Pi 4B media optimisation (OC + GPU mem) via per-file include.
# Idempotent; safe defaults; Pi 4 only.

set -euo pipefail
say(){ echo "[oneclick][05_pi_tune] $*"; }

# -------- Detect boot config location ---------------------------------------
BOOT_CFG="/boot/config.txt"
[ -f /boot/firmware/config.txt ] && BOOT_CFG="/boot/firmware/config.txt"

CFG_DIR="$(dirname "$BOOT_CFG")/config.txt.d"
CFG_FILE="$CFG_DIR/99-media-tune.conf"

# -------- Only on Raspberry Pi 4 --------------------------------------------
if ! grep -q "Raspberry Pi 4" /proc/device-tree/model 2>/dev/null; then
  say "Not a Raspberry Pi 4 — skipping Pi tuning."
  exit 0
fi

# -------- Tunables (override via env if desired) ----------------------------
ARM_FREQ="${ARM_FREQ:-2000}"        # MHz
GPU_FREQ="${GPU_FREQ:-750}"         # MHz
OVER_VOLTAGE="${OVER_VOLTAGE:-6}"   # -16..8 (firmware-accepted range)
GPU_MEM="${GPU_MEM:-320}"           # MB
DTO="${DTO:-vc4-kms-v3d,cma-512}"   # KMS + larger CMA for 4K UI/HEVC

# -------- Basic sanity on values -------------------------------------------
clamp() {
  local v=$1 lo=$2 hi=$3
  [ "$v" -lt "$lo" ] && v=$lo
  [ "$v" -gt "$hi" ] && v=$hi
  echo "$v"
}
ARM_FREQ="$(clamp "$ARM_FREQ" 1500 2200)"
GPU_FREQ="$(clamp "$GPU_FREQ" 500 800)"
OVER_VOLTAGE="$(clamp "$OVER_VOLTAGE" -16 8)"
GPU_MEM="$(clamp "$GPU_MEM" 256 512)"

# -------- Backup active boot config (once) ----------------------------------
if [ ! -f "${BOOT_CFG}.oneclick.bak" ]; then
  cp -a "$BOOT_CFG" "${BOOT_CFG}.oneclick.bak" || true
  say "Backed up $(basename "$BOOT_CFG") -> $(basename "${BOOT_CFG}.oneclick.bak")"
fi

# -------- Write per-file config ---------------------------------------------
mkdir -p "$CFG_DIR"
cat >"$CFG_FILE"<<EOF
# --- OneClick: Raspberry Pi 4B Media Optimisation ---
# Safe, common OC + graphics memory for Kodi workloads
arm_freq=${ARM_FREQ}
gpu_freq=${GPU_FREQ}
over_voltage=${OVER_VOLTAGE}
gpu_mem=${GPU_MEM}
dtoverlay=${DTO}
EOF

# -------- Ensure include in main config -------------------------------------
if ! grep -Eq '^[[:space:]]*include[[:space:]]+config\.txt\.d/\*\.conf' "$BOOT_CFG" 2>/dev/null; then
  say "Linking $(basename "$CFG_DIR")/*.conf in $(basename "$BOOT_CFG")"
  printf '\n# Include per-file configs (OneClick)\n[all]\ninclude config.txt.d/*.conf\n' >> "$BOOT_CFG"
fi

# -------- Friendly summary ---------------------------------------------------
say "Media tuning staged in: $CFG_FILE"
say "Settings: arm_freq=${ARM_FREQ} gpu_freq=${GPU_FREQ} over_voltage=${OVER_VOLTAGE} gpu_mem=${GPU_MEM} dtoverlay=${DTO}"
say "Reboot required to take effect."
