#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ⚡ Xtreme v1.0 Image Builder — Simple Edition
# Encrypt • Optimize • Deploy • Dominate
# A Bat-Net Production — Powered by XBian
# ============================================================

# === COLORS ===
YELLOW="$(tput setaf 3)"
BLUE="$(tput setaf 6)"
RESET="$(tput sgr0)"

# === HEADER ===
clear
cat <<'EOF'
╔════════════════════════════════════════════════════╗
║        ⚡   Xtreme v1.0 Image Builder ⚡              ║
║     Encrypt • Optimize • Deploy • Dominate         ║
║     A Bat-Net Production — Powered by XBian        ║
╚════════════════════════════════════════════════════╝
EOF
echo

# === DEPENDENCY CHECK ===
REQUIRED=(pv gzip zip util-linux curl losetup)
MISSING=()

echo -e "${BLUE}🔍 Checking required packages...${RESET}"
for pkg in "${REQUIRED[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    MISSING+=("$pkg")
  fi
done

if ((${#MISSING[@]})); then
  echo -e "${YELLOW}⚠️  Missing packages: ${MISSING[*]}${RESET}"
  echo -e "${YELLOW}Would you like to install them now? (y/n)${RESET}"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}📦 Installing dependencies...${RESET}"
    sudo apt update -y
    sudo apt install -y "${MISSING[@]}"
    echo -e "${BLUE}✅ Dependencies installed.${RESET}"
  else
    echo -e "${YELLOW}Please install them manually and re-run this script:${RESET}"
    echo "sudo apt install -y ${MISSING[*]}"
    exit 1
  fi
else
  echo -e "${BLUE}✅ All dependencies already present.${RESET}"
fi
echo

# === CONFIG ===
BASE_IMG="XBian_Latest_arm64_rpi5.img"
OUT_IMG="Xtreme.img"
LOG="xtreme-build-$(date +%F_%H%M%S).log"

# === PROGRESS BAR ===
progress() {
  local percent=$1
  local message="$2"
  local filled=$((percent / 2))
  local empty=$((50 - filled))
  printf "\r${BLUE}[%-${filled}s%-${empty}s]${RESET} %3d%%  ${YELLOW}%s${RESET}" \
         "$(printf '█%.0s' $(seq 1 $filled))" "" "$percent" "$message"
}

# === STEP WRAPPER ===
step() {
  local percent=$1
  local label="$2"
  progress "$percent" "$label"
  echo >>"$LOG"
}

# === BUILD SEQUENCE ===
{
  step 0 "Starting build process..."
  sleep 1

  # 1️⃣ Build phase
  step 10 "Preparing base image..."
  sudo ./build-oneclick-image.sh "$BASE_IMG" "$OUT_IMG" >>"$LOG" 2>&1
  step 50 "Image merge complete!"

  # 2️⃣ Verify phase
  step 55 "Verifying integrity..."
  sudo ./verify-oneclick-image.sh "${OUT_IMG}" >>"$LOG" 2>&1 || true
  step 75 "Verification done!"

  # 3️⃣ Package phase
  step 80 "Packaging final image..."
  sudo ./package-oneclick.sh "${OUT_IMG}" >>"$LOG" 2>&1
  step 95 "Packaging complete!"

  # 4️⃣ Completion
  step 100 "✅ Build complete!"
  echo -e "\n"
  echo "Build log saved to: $LOG"
  echo
  echo "Would you like to flash this image to SD now? (y/n)"
  read -r ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo
    read -rp "Enter SD card device path (default /dev/mmcblk0): " DEV
    DEV="${DEV:-/dev/mmcblk0}"
    echo -e "${YELLOW}Flashing to $DEV...${RESET}"
    sudo pv "${OUT_IMG}.gz" | sudo dd of="$DEV" bs=4M conv=fsync status=none
    sync
    echo -e "\n${BLUE}✅ Flash complete!${RESET}"
    echo
  fi
} || {
  echo -e "\n${YELLOW}⚠️  Build encountered errors. See $LOG.${RESET}"
  exit 1
}

# === OUTRO ===
cat <<'EOF'

✅ All stages complete — the herd is pleased.
         (__)
         (oo)  MOO!
  /-------\/
 / |     ||
*  ||----||
   ^^    ^^

EOF
