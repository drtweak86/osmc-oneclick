#!/bin/bash
set -euo pipefail

# ---- Common paths (XBian) ----
KODI_USER="${KODI_USER:-xbian}"
KODI_HOME="${KODI_HOME:-/home/${KODI_USER}/.kodi}"
ADDONS_DIR="${ADDONS_DIR:-${KODI_HOME}/addons}"
PKG_DIR="${PKG_DIR:-${ADDONS_DIR}/packages}"
LOG_TAG="${LOG_TAG:-oneclick}"

mkdir -p "$ADDONS_DIR" "$PKG_DIR" >/dev/null 2>&1 || true

log()  { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s][WARN] %s\n' "$LOG_TAG" "$*" >&2; }
die()  { printf '[%s][FATAL] %s\n' "$LOG_TAG" "$*" >&2; exit 1; }

# ---- Tiny URL fetcher for "latest" zip from a page ----
# Usage: fetch_latest_zip "https://example/releases" "repo-name-like" "/tmp/out.zip"
fetch_latest_zip() {
  local page_url="$1" match_hint="$2" out_zip="$3"
  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"

  log "Fetching latest zip from: $page_url"
  local page
  page="$(curl -fsSL -A "$ua" "$page_url")" || { warn "curl failed: $page_url"; return 1; }

  # Find first .zip that contains match_hint
  local zip_url
  zip_url="$(printf '%s' "$page" | grep -Eo 'https?://[^"]+\.zip' | grep -i "$match_hint" | head -n1 || true)"
  if [ -z "$zip_url" ]; then
    warn "No .zip link matching '$match_hint' found on $page_url"
    return 1
  fi

  log "Downloading: $zip_url"
  curl -fsSL -A "$ua" -o "$out_zip" "$zip_url" || { warn "download failed: $zip_url"; return 1; }
  [ -s "$out_zip" ] || { warn "empty zip: $out_zip"; return 1; }
  return 0
}

# ---- Install a Kodi zip by extracting into addons dir ----
# Usage: kodi_install_zip "/path/repository.xxx-1.0.0.zip"
kodi_install_zip() {
  local zip="$1"
  [ -f "$zip" ] || { warn "zip not found: $zip"; return 1; }

  log "Installing zip into $ADDONS_DIR: $(basename "$zip")"
  mkdir -p "$PKG_DIR"
  cp -f "$zip" "$PKG_DIR/" || true

  # Extract; top-level directory becomes addon id (repo or plugin)
  local tmpdir
  tmpdir="$(mktemp -d)"
  unzip -o "$zip" -d "$tmpdir" >/dev/null

  # Move contents (one or more addon dirs) into addons dir
  shopt -s nullglob
  for d in "$tmpdir"/*; do
    [ -d "$d" ] || continue
    local addon_id
    addon_id="$(basename "$d")"
    rm -rf  "$ADDONS_DIR/$addon_id"
    mv "$d" "$ADDONS_DIR/$addon_id"
    chown -R "${KODI_USER}:${KODI_USER}" "$ADDONS_DIR/$addon_id"
    log "Installed addon: $addon_id"
  done
  rm -rf "$tmpdir"
}

# ---- Light wrapper to restart Kodi on XBian ----
kodi_restart() {
  # XBian service name is "xbmc"
  if command -v service >/dev/null 2>&1; then
    service xbmc restart || true
  fi
}

# ---- Convenience: ensure a file exists with content ----
ensure_file() {
  # ensure_file /path/to/file "content"
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$*" > "$f"
}
