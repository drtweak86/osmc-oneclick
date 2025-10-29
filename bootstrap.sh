#!/usr/bin/env bash
set -euo pipefail

# 0) Be root
[ "$EUID" -ne 0 ] && exec sudo -E bash "$0" "$@"

# 1) Basics for fresh OSMC/Debian
apt-get update
apt-get install -y --no-install-recommends git curl ca-certificates

# 2) Clone or update working copy
REPO="https://github.com/drtweak86/osmc-oneclick.git"
DEST="/opt/osmc-oneclick"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --depth=1 origin main
  git -C "$DEST" reset --hard origin/main
else
  git clone --depth=1 "$REPO" "$DEST"
fi

# 3) Run installer
exec bash "$DEST/install.sh"
