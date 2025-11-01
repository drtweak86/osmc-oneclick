#!/usr/bin/env bash
# phases/05-play-bootvideo.sh — XBian-safe
# Plays /boot/matrix_boot.mp4 once at startup.
# Falls back to autoexec.py if kodi-send is missing.
# No systemctl usage (XBian uses /etc/init.d/xbmc).

set -euo pipefail

log(){ echo "[oneclick][05_play_boot] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

VID="/boot/matrix_boot.mp4"
KODI_HOME="/home/xbian/.kodi"
USER="xbian"
SERV_INIT="/etc/init.d/xbmc"

# Nothing to play? exit quietly.
[ -f "$VID" ] || { log "No $VID, skipping."; exit 0; }

# Ensure ownership paths exist for fallback
install -d -m 0755 "$KODI_HOME"/{media,userdata}
chown -R "$USER:$USER" "$KODI_HOME" || true

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

# Wait for Kodi to be running (pgrep), up to ~60s
wait_for_kodi(){
  for _ in $(seq 1 60); do
    if pgrep -x kodi.bin >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Try to make Kodi play via kodi-send if present
play_with_kodisent(){
  has_cmd kodi-send || return 1
  log "Attempting playback with kodi-send…"
  kodi-send --action="PlayMedia($VID)" || return 1
  sleep 8
  kodi-send --action="PlayerControl(Stop)" || true
  return 0
}

# Fallback: create a one-shot autoexec.py that deletes itself after playing
install_autoexec_fallback(){
  local AE="$KODI_HOME/userdata/autoexec.py"
  log "Installing one-shot autoexec.py fallback…"
  cat > "$AE" <<'PY'
import xbmc, xbmcgui, os, time, shutil
VIDEO = xbmc.translatePath('special://home/media/matrix_boot.mp4')
# copy from /boot if not already present
boot_vid = '/boot/matrix_boot.mp4'
home_vid = xbmc.translatePath('special://home/media/matrix_boot.mp4')
try:
    if os.path.exists(boot_vid) and not os.path.exists(home_vid):
        os.makedirs(os.path.dirname(home_vid), exist_ok=True)
        shutil.copy2(boot_vid, home_vid)
except Exception as e:
    xbmc.log(f"autoexec copy failed: {e}", xbmc.LOGWARNING)

p = xbmc.Player()
if os.path.exists(VIDEO):
    p.play(VIDEO)
    for _ in range(100):
        if p.isPlaying(): break
        time.sleep(0.1)
    time.sleep(7)
# remove self so it only happens once
try:
    os.remove(xbmc.translatePath('special://home/userdata/autoexec.py'))
except Exception:
    pass
PY
  chown "$USER:$USER" "$AE"
}

# Ensure the video is also in home/media for skins that expect it
if [ ! -f "$KODI_HOME/media/matrix_boot.mp4" ]; then
  cp -f "$VID" "$KODI_HOME/media/matrix_boot.mp4" || true
  chown "$USER:$USER" "$KODI_HOME/media/matrix_boot.mp4" || true
fi

# Kick xbmc once so it (re)spawns if not up yet (ignore errors if not present)
if [ -x "$SERV_INIT" ]; then
  "$SERV_INIT" status >/dev/null 2>&1 || "$SERV_INIT" start || true
fi

if wait_for_kodi; then
  if play_with_kodisent; then
    log "Played via kodi-send."
    exit 0
  else
    warn "kodi-send unavailable or failed; using autoexec fallback."
    install_autoexec_fallback
    # restart xbmc to pick up autoexec
    [ -x "$SERV_INIT" ] && "$SERV_INIT" restart || true
    exit 0
  fi
else
  warn "Kodi never became ready; installing autoexec fallback for next start."
  install_autoexec_fallback
  exit 0
fi
