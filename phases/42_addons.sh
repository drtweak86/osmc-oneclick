#!/usr/bin/env bash
# phases/42_addons.sh
# Install Kodi 3rd party repos first, then add-ons from those repos.
# Uses helpers from 31_helpers.sh (install_repo_from_url, install_addon, fetch_latest_zip, log, etc.)

set -euo pipefail
. "$(dirname "$0")/31_helpers.sh"

log "[addons] Starting add-on repo + addon installation"

# --- Repositories (name | homepage | pattern) ---
# We fetch the page and auto-detect the latest *.zip that matches the pattern.
# If a repo publishes a single zip, pattern can be just '\.zip$'
REPOS=(
  "Umbrella|https://umbrella-plugins.github.io/|repository\.umbrella.*\.zip"
  "Nixgates (Seren)|https://nixgates.github.io/packages/|repository\.nixgates.*\.zip"
  "A4KSubtitles|https://a4k-openproject.github.io/a4kSubtitles/packages/|repository\.a4k.*\.zip"
  "Otaku|https://goldenfreddy0703.github.io/repository.otaku/|repository\.otaku.*\.zip"
  "CocoScrapers|https://cocojoe2411.github.io/|repository\.cocoscrapers.*\.zip"
  "OptiKlean|https://www.digitalking.it/kodi-repo/|repository\.optiklean.*\.zip"
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
# These IDs come from their repos; Kodi will resolve dependencies and keep them updated from the repos.
ADDONS=(
  "plugin.video.umbrella"
  "plugin.video.seren"
  "service.subtitles.a4ksubtitles"
  "plugin.video.otaku"
  "script.module.cocoscrapers"
  "script.trakt"
  "script.artwork.dump"
  "plugin.program.optiklean"
)

for addon in "${ADDONS[@]}"; do
  log "[addons] Installing add-on: $addon"
  install_addon "$addon" || warn "[addons] Install returned non-zero for $addon (might already be installed)."
done

# --- Seren BBviking update (zip, installed AFTER Seren) ---
# The site hosts a zip; we’ll fetch the most recent zip on the page and feed it to “Install from zip”.
BBV_PAGE="https://bbviking.github.io/"
BBV_PATTERN="\.zip$"
BBV_ZIP="$(fetch_latest_zip "$BBV_PAGE" "$BBV_PATTERN" || true)"
if [[ -n "${BBV_ZIP:-}" ]]; then
  log "[addons] Applying BBviking Seren update from $BBV_ZIP"
  install_zip_from_url "$BBV_ZIP" || warn "[addons] BBviking update failed (zip format might have changed)."
else
  warn "[addons] Could not find BBviking zip at $BBV_PAGE; skipping Seren patch."
fi

log "[addons] All done."
