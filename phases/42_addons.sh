#!/usr/bin/env bash
# phases/42_addons.sh
# Install 3rd-party repositories, add-ons, apply Seren BBviking patch,
# trigger Trakt OAuth, then switch to Arctic Fuse 2.
#
# Requires helpers from 31_helpers.sh:
#   - log, warn
#   - fetch_latest_zip PAGE PATTERN
#   - install_repo_from_url URL
#   - install_addon ADDON_ID
#   - install_zip_from_url URL

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

log "[addons] Starting add-on repo + addon installation"

# --- Repositories (name | homepage | pattern) ---
REPOS=(
  "Umbrella|https://umbrella-plugins.github.io/|repository\.umbrella.*\.zip"
  "Nixgates (Seren)|https://nixgates.github.io/packages/|repository\.nixgates.*\.zip"
  "A4KSubtitles|https://a4k-openproject.github.io/a4kSubtitles/packages/|repository\.a4k.*\.zip"
  "Otaku|https://goldenfreddy0703.github.io/repository.otaku/|repository\.otaku.*\.zip"
  "CocoScrapers|https://cocojoe2411.github.io/|repository\.cocoscrapers.*\.zip"
  "OptiKlean|https://www.digitalking.it/kodi-repo/|repository\.optiklean.*\.zip"
  "jurialmunkey|https://jurialmunkey.github.io/repository.jurialmunkey/|repository\.jurialmunkey.*\.zip"
)

for entry in "${REPOS[@]}"; do
  IFS="|" read -r NAME PAGE PATTERN <<<"$entry"
  log "[addons] Repo: $NAME"
  ZIP_URL="$(fetch_latest_zip "$PAGE" "$PATTERN" || true)"
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
  install_addon "$addon" || warn "[addons] Install returned non-zero for $addon (might already be installed)."
done

# --- Seren BBviking update (apply immediately after Seren) ---
BBV_PAGE="https://bbviking.github.io/"
BBV_PATTERN="\.zip$"
BBV_ZIP="$(fetch_latest_zip "$BBV_PAGE" "$BBV_PATTERN" || true)"
if [[ -n "${BBV_ZIP:-}" ]]; then
  log "[addons] Applying BBviking Seren update from $BBV_ZIP"
  install_zip_from_url "$BBV_ZIP" || warn "[addons] BBviking update failed (zip format might have changed)."
else
  warn "[addons] Could not find BBviking zip at $BBV_PAGE; skipping Seren patch."
fi

# --- Trakt: enable + trigger OAuth popup ---
KODI_SEND="/usr/bin/kodi-send"

if [[ -x "$KODI_SEND" ]]; then
  # Ensure Kodi is running so JSON-RPC works
  if ! systemctl is-active --quiet mediacenter; then
    log "[addons] Kodi not running — starting mediacenter to finish Trakt auth"
    systemctl start mediacenter
    sleep 15
  fi

  log "[addons] Enabling Trakt and triggering OAuth"
  sudo -u osmc "$KODI_SEND" -a "InstallAddon(script.trakt)" || true
  sudo -u osmc "$KODI_SEND" -a "EnableAddon(script.trakt)" || true
  # Running the add-on opens the 'go to trakt.tv/activate' code prompt
  sudo -u osmc "$KODI_SEND" -a "RunScript(script.trakt)" || true
  sudo -u osmc "$KODI_SEND" -a "Notification(Setup,Trakt installed — follow on-screen code to link,8000)" || true
else
  warn "[addons] kodi-send not found; skipping Trakt OAuth trigger"
fi

# --- Switch Kodi to Arctic Fuse 2 (or Horizon 2) ---
PREFERRED_SKIN="skin.arctic.fuse.2"   # or: skin.arctic.horizon.2

if [[ -x "$KODI_SEND" ]]; then
  # Make sure Kodi is up so JSON-RPC works
  if ! systemctl is-active --quiet mediacenter; then
    log "[addons] Kodi not running — starting mediacenter to switch skin"
    systemctl start mediacenter
    sleep 15
  fi

  # Install + enable chosen skin (safe if already installed)
  sudo -u osmc "$KODI_SEND" -a "InstallAddon(${PREFERRED_SKIN})" || true
  sudo -u osmc "$KODI_SEND" -a "EnableAddon(${PREFERRED_SKIN})" || true

  # Ask Kodi to switch skin (user will see the 'Keep this skin?' prompt on screen)
  sudo -u osmc "$KODI_SEND" -a "SetProperty(lookandfeel.skin,${PREFERRED_SKIN},10025)" || true
  sudo -u osmc "$KODI_SEND" -a "Notification(Skin,Switching to Arctic…,8000)" || true
else
  warn "[addons] kodi-send not found; skipping skin switch"
fi

log "[addons] All done."
