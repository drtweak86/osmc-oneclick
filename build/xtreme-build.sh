#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/build/xtreme.cfg"

# Ensure deps and workdir
sudo apt-get update -qq
sudo apt-get install -y pv whiptail rsync gzip util-linux >/dev/null
mkdir -p "$WORKDIR"

# Pretty splash
clear
cat <<'SPLASH'
╔════════════════════════════════════════════════════╗
║        ⚡  Xtreme v1.0 Image Builder ⚡             ║
║     Encrypt • Optimize • Deploy • Dominate         ║
║     A Bat-Net Production — Powered by XBian        ║
╚════════════════════════════════════════════════════╝
SPLASH
sleep 1

# 1) Prep base
TMPDIR="$WORKDIR" bash "$ROOT/01-prep-base.sh" --base "$BASE_IMG" --workdir "$WORKDIR" >/dev/null

# 2) Inject assets
bash "$ROOT/02-inject-assets.sh" --basepath "$(cat "$WORKDIR/base.path")" --workdir "$WORKDIR" --repo "$ROOT"

# 3) Pack + flash
bash "$ROOT/03-pack-and-flash.sh" --basepath "$(cat "$WORKDIR/base.path")" --workdir "$WORKDIR" --out "$OUT_IMG" --device "$DEFAULT_DEV"
