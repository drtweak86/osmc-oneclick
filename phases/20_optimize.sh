#!/usr/bin/env bash
set -euo pipefail

# Light, safe defaults for Pi media use
apt-get install -y --no-install-recommends rng-tools

# GPU memory & performance tweaks (only if on Pi/OSMC)
if grep -qi raspberry /proc/cpuinfo 2>/dev/null; then
  CFG="/boot/config.txt"
  cp -n "$CFG" "${CFG}.orig" || true
  sed -i '/^gpu_mem=/d' "$CFG"
  echo "gpu_mem=320" >> "$CFG"               # enough for HEVC UI work
  sed -i '/^arm_freq=/d;/^over_voltage=/d' "$CFG"
  # (No overclock by default; we’ll add a tuned profile later if you want)
fi

# Kernel net queue/sockets (conservative)
SYS=/etc/sysctl.d/99-osmc-oneclick.conf
cat >"$SYS" <<'EOS'
net.core.rmem_max=2500000
net.core.wmem_max=2500000
net.ipv4.tcp_rmem=4096 87380 2097152
net.ipv4.tcp_wmem=4096 65536 2097152
net.ipv4.tcp_congestion_control=bbr
EOS
sysctl --system || true

# DNS cache for snappier metadata lookups
apt-get install -y --no-install-recommends unbound
systemctl enable --now unbound || true
