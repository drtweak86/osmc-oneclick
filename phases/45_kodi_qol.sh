#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/45_kodi_qol.sh
# Kodi QoL tweaks for streaming on Pi/OSMC (Omega):
# - Adjust refresh rate (on start/stop)
# - Disable “sync playback to display”
# - Conservative HQ scalers (10%)
# - Enable audio passthrough, auto-detect passthrough device to match current audio device
# - Enable common passthrough codecs (AC3, EAC3, DTS, DTS-HD, TrueHD)
# Idempotent via autoexec.py (runs once, then renames to autoexec_done.py)

set -euo pipefail
log(){ echo "[oneclick][45_kodi_qol] $*"; }
warn(){ echo "[oneclick][WARN] $*">&2; }

USER="xbian"
KODI_HOME="/home/${USER}/.kodi"
USERDATA="${KODI_HOME}/userdata"
AUTOEXEC="${USERDATA}/autoexec.py"
AUTOEXEC_DONE="${USERDATA}/autoexec_done.py"

mkdir -p "$USERDATA"

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
set_setting("videoscreen.adjustrefreshrate", 1)  # On start/stop
set_setting("videoscreen.hqscalers", 10)        # 10% HQ scalers
set_setting("videoplayer.smoothvideo", False)   # Disable sync playback to display

# --- Audio Passthrough: enable and align passthrough device with current audio device ---
set_setting("audiooutput.passthrough", True)

# Detect current audio device and re-use for passthroughdevice
adev = get_setting("audiooutput.audiodevice")
if isinstance(adev, str) and len(adev) > 0:
    set_setting("audiooutput.passthroughdevice", adev)

# Enable common passthrough codecs (soundbar/AVR-capable)
# (Kodi will ignore unsupported ones silently)
for k in [
    "audiooutput.ac3passthrough",
    "audiooutput.eac3passthrough",
    "audiooutput.dtspassthrough",
    "audiooutput.dtshdpassthrough",
    "audiooutput.truehdpassthrough"
]:
    set_setting(k, True)

# Dolby transcode (useful if AC3 is desired from non-AC3 sources)
set_setting("audiooutput.eac3transcode", True)

# Toast confirm
try:
    dev = get_setting("audiooutput.passthroughdevice") or "Auto"
    msg = u"Refresh=Start/Stop · HQ=10 · Passthrough=On · Dev={}".format(dev)
    xbmc.executebuiltin('Notification(QoL,{},9000)'.format(msg))
except Exception:
    pass

# Self-disable
try:
    SELF = xbmc.translatePath('special://profile/autoexec.py')
    DONE = xbmc.translatePath('special://profile/autoexec_done.py')
    if os.path.exists(SELF):
        shutil.move(SELF, DONE)
except Exception:
    pass
PY

chown "${USER}:${USER}" "$AUTOEXEC"
chmod 0644 "$AUTOEXEC"

# Ensure Kodi is running so JSON-RPC applies now (otherwise it will apply next start)
if ! systemctl is-active --quiet xbmc; then
  log "Starting xbmc so QoL settings can apply…"
  systemctl start xbmc
  sleep 10
fi

log "QoL autoexec installed — it will apply once, toast the chosen device, then disable itself."
exit 0
