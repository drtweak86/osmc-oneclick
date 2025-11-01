#!/usr/bin/env bash
# phases/45_kodi_qol.sh
# Kodi QoL tweaks (Omega): refresh rate on start/stop, disable sync-to-display,
# HQ scalers 10%, enable passthrough + codecs, run once via autoexec.py.
set -euo pipefail
log(){ echo "[oneclick][45_kodi_qol] $*"; }
warn(){ echo "[oneclick][WARN] $*" >&2; }

KODI_USER="${KODI_USER:-xbian}"
KODI_HOME="/home/${KODI_USER}/.kodi"
USERDATA="${KODI_HOME}/userdata"
AUTOEXEC="${USERDATA}/autoexec.py"
AUTOEXEC_DONE="${USERDATA}/autoexec_done.py"

mkdir -p "$USERDATA"

# Pick service name: XBian uses 'xbmc', OSMC uses 'mediacenter'
KODI_SVC="xbmc"
if systemctl list-unit-files 2>/dev/null | grep -q '^mediacenter\.service'; then
  KODI_SVC="mediacenter"
fi

# Skip if already applied
if [ -f "$AUTOEXEC_DONE" ]; then
  log "QoL autoexec already applied; skipping."
  exit 0
fi

cat >"$AUTOEXEC"<<'PY'
# -*- coding: utf-8 -*-
# OneClick QoL settings for Kodi (runs once, then disables itself)
import json, os, xbmc, shutil

def jrpc(method, params=None):
    payload = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        payload["params"] = params
    res = xbmc.executeJSONRPC(json.dumps(payload))
    try:
        return json.loads(res)
    except Exception:
        return {}

def set_setting(key, value):
    try:
        jrpc("Settings.SetSettingValue", {"setting": key, "value": value})
    except Exception:
        pass

def get_setting(key):
    try:
        res = jrpc("Settings.GetSettingValue", {"setting": key})
        return res.get("result", {}).get("value", None)
    except Exception:
        return None

# --- Core QoL video settings ---
set_setting("videoscreen.adjustrefreshrate", 1)   # On start/stop
set_setting("videoscreen.hqscalers", 10)          # 10% HQ scalers
set_setting("videoplayer.smoothvideo", False)     # Disable sync playback to display

# --- Audio Passthrough ---
set_setting("audiooutput.passthrough", True)

# Use current audio device as passthrough device (if present)
adev = get_setting("audiooutput.audiodevice")
if isinstance(adev, str) and adev:
    set_setting("audiooutput.passthroughdevice", adev)

# Enable common passthrough codecs (ignored if unsupported)
for k in [
    "audiooutput.ac3passthrough",
    "audiooutput.eac3passthrough",
    "audiooutput.dtspassthrough",
    "audiooutput.dtshdpassthrough",
    "audiooutput.truehdpassthrough",
]:
    set_setting(k, True)

# Optionally transcode to AC3 from non-AC3
set_setting("audiooutput.eac3transcode", True)

# Toast + self-disable
try:
    dev = get_setting("audiooutput.passthroughdevice") or "Auto"
    msg = u"Refresh=Start/Stop · HQ=10 · Passthrough=On · Dev={}".format(dev)
    xbmc.executebuiltin('Notification(QoL,{},9000)'.format(msg))
except Exception:
    pass

try:
    SELF = xbmc.translatePath('special://profile/autoexec.py')
    DONE = xbmc.translatePath('special://profile/autoexec_done.py')
    if os.path.exists(SELF):
        shutil.move(SELF, DONE)
except Exception:
    pass
PY

chown "${KODI_USER}:${KODI_USER}" "$AUTOEXEC"
chmod 0644 "$AUTOEXEC"

# Ensure Kodi is running so JSON-RPC applies now (otherwise next start)
if ! systemctl is-active --quiet "$KODI_SVC"; then
  log "Starting $KODI_SVC so QoL settings can apply…"
  systemctl start "$KODI_SVC" || warn "Could not start $KODI_SVC (will apply on next launch)"
  sleep 10 || true
fi

log "QoL autoexec installed — it will apply once, toast, then disable itself."
