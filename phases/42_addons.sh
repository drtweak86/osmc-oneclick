#!/usr/bin/env bash
set -euo pipefail

# Requires: kodi-send available and Kodi running (OSMC service usually is).
# This phase:
#  - Fetches latest repository ZIPs for Umbrella, Nixgates (Seren), A4KSubtitles, Otaku (Hooty), CoCo Scrapers
#  - Installs each repo ZIP via Kodi
#  - Installs key add-ons from those repos: Umbrella, Seren, Trakt, Otaku, CoCo Scrapers, A4KSubtitles, Artwork Dump
#  - Applies BBviking Seren update ZIP after Seren

KODI_BIN="$(command -v kodi-send || true)"
if [[ -z "${KODI_BIN}" ]]; then
  echo "[addons] kodi-send not found; aborting."
  exit 1
fi

WORK=/tmp/kodi-repos
mkdir -p "$WORK"

kodi_install_zip() {
  local zip="$1"
  echo "[addons] Installing ZIP in Kodi: $zip"
  "$KODI_BIN" --action="InstallFromZip($zip)" >/dev/null
  # Let Kodi process
  sleep 4
}

kodi_install_addon() {
  local addon_id="$1"
  echo "[addons] Installing add-on: $addon_id"
  "$KODI_BIN" --action="InstallAddon($addon_id)" >/dev/null || true
  sleep 2
}

fetch_latest_zip() {
  # Scrape an index page for a repository zip pattern and return a local path to the downloaded file
  local base_url="$1" pattern="$2" out_name="$3"
  local page tmpzip
  page="$(mktemp)"
  curl -fsSL "$base_url" -o "$page"

  # Find the first matching zip (prefer highest-looking version if multiple appear)
  local rel
  rel="$(grep -Eo "${pattern}" "$page" | sort -Vr | head -n1 || true)"
  if [[ -z "$rel" ]]; then
    echo "[addons] ERROR: could not find zip by pattern '$pattern' at $base_url" >&2
    rm -f "$page"
    return 1
  fi

  # If rel is a relative path, build absolute
  if [[ "$rel" != http* ]]; then
    # strip leading './' or '/' if present
    rel="${rel#./}"
    rel="${rel#/}"
    rel="${base_url%/}/$rel"
  fi

  tmpzip="$WORK/$out_name"
  echo "[addons] Downloading: $rel"
  curl -fsSL "$rel" -o "$tmpzip"
  rm -f "$page"
  echo "$tmpzip"
}

# 1) Umbrella repo (https://umbrellaplug.github.io/)
UMBRELLA_ZIP="$(fetch_latest_zip "https://umbrellaplug.github.io/" 'repository\.umbrella-[0-9.]+\.zip' "repository.umbrella.zip")"
kodi_install_zip "$UMBRELLA_ZIP"

# 2) Nixgates repo (Seren) (https://nixgates.github.io/packages/)
NIX_ZIP="$(fetch_latest_zip "https://nixgates.github.io/packages/" 'repository\.nixgates-[0-9.]+\.zip' "repository.nixgates.zip")"
kodi_install_zip "$NIX_ZIP"

# 3) A4KSubtitles repo (https://a4k-openproject.github.io/a4kSubtitles/packages/)
A4K_ZIP="$(fetch_latest_zip "https://a4k-openproject.github.io/a4kSubtitles/packages/" 'a4kSubtitles[-_]repository[^"]*\.zip' "a4kSubtitles-repository.zip")"
kodi_install_zip "$A4K_ZIP"

# 4) Otaku (Hooty) repo (https://goldenfreddy0703.github.io/repository.hooty/)
# This one typically exposes a stable filename "repository.hooty.zip"
HOOTY_ZIP="$(fetch_latest_zip "https://goldenfreddy0703.github.io/repository.hooty/" 'repository\.hooty[^"]*\.zip' "repository.hooty.zip")"
kodi_install_zip "$HOOTY_ZIP"

# 5) CoCo Scrapers repo (https://cocojoe2411.github.io/)
COCO_ZIP="$(fetch_latest_zip "https://cocojoe2411.github.io/" 'repository\.cocoscrapers-[0-9.]+\.zip' "repository.cocoscrapers.zip")"
kodi_install_zip "$COCO_ZIP"

# --- Install add-ons from repos ---
# Umbrella
kodi_install_addon "plugin.video.umbrella"

# Seren (from Nixgates)
kodi_install_addon "plugin.video.seren"

# Trakt (official repo ID)
kodi_install_addon "script.trakt"

# Otaku
kodi_install_addon "plugin.video.otaku"

# CoCo Scrapers core (module IDs vary; try both common ids)
kodi_install_addon "script.module.cocoscrapers" || true
kodi_install_addon "script.module.cocoscrapers.lite" || true

# A4KSubtitles
kodi_install_addon "service.subtitles.a4ksubtitles"

# Artwork Dump
kodi_install_addon "script.artwork.dump"

# --- BBviking Seren update (overlays as a direct plugin zip) ---
# Source: https://bbviking.github.io/  (direct plugin zip published there)
BB_PAGE="https://bbviking.github.io/"
BB_ZIP="$(fetch_latest_zip "$BB_PAGE" 'plugin\.video\.seren\.[0-9.]+\.zip' "plugin.video.seren-bbviking.zip")"
if [[ -n "$BB_ZIP" ]]; then
  kodi_install_zip "$BB_ZIP"
else
  echo "[addons] BBviking Seren zip not found; skipping."
fi

echo "[addons] Repositories and add-ons install phase complete."
