#!/usr/bin/env bash
# install.sh — one-shot installer for OSMC OneClick
# - Installs prerequisites (curl, unzip, jq, certs)
# - Ensures latest rclone
# - Runs add-ons + skin/fonts phases
# - Enables backup timer if unit files are present

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

require_root() {
  if [[ ${EUID:-0} -ne 0 ]]; then
    echo "[oneclick][install] Please run with sudo/root."
    exit 1
  fi
}

log() { echo "[oneclick][install] $*"; }

require_root

log "Installing prerequisites (curl, unzip, jq, ca-certificates)…"
apt-get update -y || true
apt-get install -y curl unzip jq ca-certificates || true

log "Ensuring latest rclone…"
# Safe to re-run; script handles upgrade-in-place
curl -fsSL https://rclone.org/install.sh | bash

log "Marking phase scripts executable…"
chmod +x "$REPO_DIR"/phases/*.sh || true

# ---- Run phases ----
if [[ -x "$REPO_DIR/phases/42_addons.sh" ]]; then
  log "Running add-ons phase (42)…"
  bash "$REPO_DIR/phases/42_addons.sh"
else
  log "WARN: phases/42_addons.sh not found or not executable — skipping."
fi

if [[ -x "$REPO_DIR/phases/43_fonts.sh" ]]; then
  log "Running fonts phase (43)…"
  bash "$REPO_DIR/phases/43_fonts.sh"
else
  log "WARN: phases/43_fonts.sh not found or not executable — skipping."
fi

# ---- Enable timers/services if present ----
if systemctl list-unit-files | grep -q '^oneclick-backup.service'; then
  log "Reloading systemd units and enabling backup timer…"
  systemctl daemon-reload
  systemctl enable --now oneclick-backup.timer || true
fi

log "Install complete. Trakt popup will appear in Kodi; follow the on-screen code to link your account."
