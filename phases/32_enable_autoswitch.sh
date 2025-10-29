#!/usr/bin/env bash
set -euo pipefail
log(){ echo -e "[oneclick][32_enable_autoswitch] $*"; }

SVC=/etc/systemd/system/wg-autoswitch.service
TMR=/etc/systemd/system/wg-autoswitch.timer
SRC_DIR="/opt/osmc-oneclick/systemd"

install_unit(){
  local src="$1" dst="$2"
  if [ -f "$src" ]; then
    cp -f "$src" "$dst"
  fi
}

install_unit "$SRC_DIR/wg-autoswitch.service" "$SVC"
install_unit "$SRC_DIR/wg-autoswitch.timer"   "$TMR"
systemctl daemon-reload
systemctl enable --now wg-autoswitch.timer

systemctl status wg-autoswitch.timer --no-pager || true
log "Autoswitch timer enabled."
