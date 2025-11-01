#!/usr/bin/env bash
# phases/42_addons.sh — XBian-safe add-on bootstrap
# Requires helpers in 31_helpers.sh (log, warn, fetch_latest_zip, install_repo_from_url, install_addon, install_zip_from_url)

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

KODI_USER="${KODI_USER:-xbian}"
KODI_SEND_BIN="$(command -v kodi-send || true)"

log "[addons] Starting add-on repo + add-on installation (XBian mode)"

# --- Try to ensure Kodi is up (XBian uses Upstart 'xbmc' service; no systemd) ---
if command -v service >/dev/null 2>&1; then
  # best-effort start; harmless if already running
  service xbmc start >/dev/null 2>&1 || true
  sleep 10
fi

# --- Repositories (NAME | PAGE | REGEX_PATTERN) ---
REPOS=(
  "Umbrella|https://umbrella-plugins.github.io/|repository\.umbrella.*\.zip"
  "Nixgates (Seren)|https://nixgates.github.io/packages/|repository\.nixgates.*\.zip"
  "A4KSubtitles|https://a4k-openproject.github.io/a4kSubtitles/packages/|repository\.a4k.*\.zip"
  "Otaku|https://goldenfreddy0703.github.io/repository.otaku/|repository\.otaku.*\.zip"
  "CocoScrapers|https://cocojoe2411.github.io/|repository\.cocoscrapers.*\.zip"
  "OptiKlean|https://www.digitalking.it/kodi-repo/|repository\.optiklean.*\.zip"
  "jurialmunkey|https://jurialmunkey.github.io/repository.jurialmunkey/|repository\.jurialmunkey.*\.zip"
  # Rector Stuff (Artwork Dump lives here). Fallback to stable URL if scraping fails.
  "RectorStuff|https://github.com/rmrector/repository.rector.stuff/raw/master/latest/|repository\.rector\.stuff.*\.zip"
)

for entry in "${REPOS[@]}"; do
  IFS="|" read -r NAME PAGE PATTERN <<<"$entry"
  log "[addons] Repo: $NAME"
  ZIP_URL="$(fetch_latest_zip "$PAGE" "$PATTERN" || true)"

  if [[ -z "${ZIP_URL:-}" && "$NAME" == "RectorStuff" ]]; then
    ZIP_URL="https://github.com/rmrector/repository.rector.stuff/raw/master/latest/repository.rector.stuff-latest.zip"
    log "[addons] RectorStuff: using fallback zip URL"
  fi

  if [[ -z "${ZIP_URL:-}" ]]; then
    warn "[addons] Could not auto-detect repo zip for $NAME from $PAGE (pattern: $PATTERN). Skipping."
    continue
  fi

  log "[addons] Installing repo from: $ZIP_URL"
  install_repo_from_url "$ZIP_URL"
done

# --- Add-ons to install (by add-on id) ---
ADDONS=(
  "plugin.video.umbrella"
  "plugin.video.seren"
  "service.subtitles.a4ksubtitles"
  "plugin.video.otaku"
  "script.module.cocoscrapers"
  "script.trakt"
  "script.artwork.dump"
  "plugin.program.optiklean"
  "skin.arctic.fuse.2"
)

for addon in "${ADDONS[@]}"; do
  log "[addons] Installing add-on: $addon"
  install_addon "$addon" || warn "[addons] Non-zero exit for $addon (may already be installed)."
done

# --- Trakt: enable + trigger OAuth popup (only if kodi-send exists) ---
if [[ -n "$KODI_SEND_BIN" ]]; then
  log "[addons] Enabling Trakt and triggering OAuth"
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "InstallAddon(script.trakt)" || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "EnableAddon(script.trakt)"  || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "RunScript(script.trakt)"     || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "Notification(Setup,Trakt installed — follow on-screen code to link,8000)" || true
else
  warn "[addons] kodi-send not found; skipping Trakt OAuth trigger"
fi

# --- Switch Kodi to Arctic Fuse 2 (ask user to confirm in UI) ---
PREFERRED_SKIN="skin.arctic.fuse.2"
if [[ -n "$KODI_SEND_BIN" ]]; then
  log "[addons] Installing + enabling preferred skin"
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "InstallAddon(${PREFERRED_SKIN})" || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "EnableAddon(${PREFERRED_SKIN})"  || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "SetProperty(lookandfeel.skin,${PREFERRED_SKIN},10025)" || true
  sudo -u "$KODI_USER" "$KODI_SEND_BIN" -a "Notification(Skin,Switching to Arctic…,8000)" || true
else
  warn "[addons] kodi-send not found; skipping skin switch"
fi

# --- Seren BBviking patch (optional) ---
BBV_PAGE="https://bbviking.github.io/"
BBV_PATTERN="\.zip$"
BBV_ZIP="$(fetch_latest_zip "$BBV_PAGE" "$BBV_PATTERN" || true)"
if [[ -n "${BBV_ZIP:-}" ]]; then
  log "[addons] Applying BBviking Seren update from $BBV_ZIP"
  install_zip_from_url "$BBV_ZIP" || warn "[addons] BBviking update failed (zip format might have changed)."
else
  warn "[addons] Could not find BBviking zip at $BBV_PAGE; skipping Seren patch."
fi

log "[addons] Done."
