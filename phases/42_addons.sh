#!/usr/bin/env bash
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
set -euo pipefail
. /opt/osmc-oneclick/phases/31_helpers.sh || true
. /opt/osmc-oneclick/phases/31_toast.sh || true
# phases/42_addons.sh
# Install Kodi 3rd-party repos first, then add-ons from those repos.
# Relies on helpers in 31_helpers.sh: log, warn, fetch_latest_zip, install_repo_from_url, install_addon, install_zip_from_url

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

log "[addons] Starting add-on repo + addon installation"

# --- Repositories (NAME | PAGE | REGEX_PATTERN) ---
# We fetch the page and auto-detect the latest *.zip that matches PATTERN.
REPOS=(
  "Umbrella|https://umbrella-plugins.github.io/|repository\.umbrella.*\.zip"
  "Nixgates (Seren)|https://nixgates.github.io/packages/|repository\.nixgates.*\.zip"
  "A4KSubtitles|https://a4k-openproject.github.io/a4kSubtitles/packages/|repository\.a4k.*\.zip"
  "Otaku|https://goldenfreddy0703.github.io/repository.otaku/|repository\.otaku.*\.zip"
  "CocoScrapers|https://cocojoe2411.github.io/|repository\.cocoscrapers.*\.zip"
  "OptiKlean|https://www.digitalking.it/kodi-repo/|repository\.optiklean.*\.zip"
  "jurialmunkey|https://jurialmunkey.github.io/repository.jurialmunkey/|repository\.jurialmunkey.*\.zip"
  # Rector Stuff (Artwork Dump lives here). We’ll also fall back to a direct zip if scraping fails.
  "RectorStuff|https://github.com/rmrector/repository.rector.stuff/raw/master/latest/|repository\.rector\.stuff.*\.zip"
)

for entry in "${REPOS[@]}"; do
  IFS="|" read -r NAME PAGE PATTERN <<<"$entry"
  log "[addons] Repo: $NAME"
  ZIP_URL="$(fetch_latest_zip "$PAGE" "$PATTERN" || true)"

  # Fallback for Rector Stuff if scraping fails (path is stable)
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
# Kodi will resolve dependencies and keep them updated from the repos.
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

# --- Trakt: enable + trigger OAuth popup (so you get the on-screen code) ---
KODI_SEND="/usr/bin/kodi-send"
if [[ -x "$KODI_SEND" ]]; then
  # Ensure Kodi is running so JSON-RPC works
  if ! systemctl is-active --quiet xbmc; then
    log "[addons] Kodi not running — starting xbmc to finish Trakt auth"
    systemctl start xbmc
    sleep 15
  fi

  log "[addons] Enabling Trakt and triggering OAuth"
  sudo -u xbian "$KODI_SEND" -a "InstallAddon(script.trakt)" || true
  sudo -u xbian "$KODI_SEND" -a "EnableAddon(script.trakt)" || true
  sudo -u xbian "$KODI_SEND" -a "RunScript(script.trakt)" || true
  sudo -u xbian "$KODI_SEND" -a "Notification(Setup,Trakt installed — follow on-screen code to link,8000)" || true
else
  warn "[addons] kodi-send not found; skipping Trakt OAuth trigger"
fi

# --- Switch Kodi to Arctic Fuse 2 (or Horizon 2) ---
PREFERRED_SKIN="skin.arctic.fuse.2"   # alternative: skin.arctic.horizon.2
if [[ -x "$KODI_SEND" ]]; then
  if ! systemctl is-active --quiet xbmc; then
    log "[addons] Kodi not running — starting xbmc to switch skin"
    systemctl start xbmc
    sleep 15
  fi
  # Install + enable chosen skin (safe if already installed)
  sudo -u xbian "$KODI_SEND" -a "InstallAddon(${PREFERRED_SKIN})" || true
  sudo -u xbian "$KODI_SEND" -a "EnableAddon(${PREFERRED_SKIN})" || true

  # Ask Kodi to switch skin (user will see the 'Keep this skin?' prompt)
  sudo -u xbian "$KODI_SEND" -a "SetProperty(lookandfeel.skin,${PREFERRED_SKIN},10025)" || true
  sudo -u xbian "$KODI_SEND" -a "Notification(Skin,Switching to Arctic…,8000)" || true
else
  warn "[addons] kodi-send not found; skipping skin switch"
fi

# --- Seren BBviking update (zip, installed AFTER Seren) ---
BBV_PAGE="https://bbviking.github.io/"
BBV_PATTERN="\.zip$"
BBV_ZIP="$(fetch_latest_zip "$BBV_PAGE" "$BBV_PATTERN" || true)"
if [[ -n "${BBV_ZIP:-}" ]]; then
  log "[addons] Applying BBviking Seren update from $BBV_ZIP"
  install_zip_from_url "$BBV_ZIP" || warn "[addons] BBviking update failed (zip format might have changed)."
else
  warn "[addons] Could not find BBviking zip at $BBV_PAGE; skipping Seren patch."
fi

# --- Friendly heads-up for Artwork Dump usage ---
if [[ -x "$KODI_SEND" ]]; then
  sudo -u xbian "$KODI_SEND" -a "Notification(Artwork Dump,Installed — run from Add-ons to fetch artwork,9000)" || true
fi

log "[addons] All done."
