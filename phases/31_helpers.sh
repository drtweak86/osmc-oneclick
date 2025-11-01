#!/usr/bin/env bash
# phases/31_helpers.sh — XBian-safe helpers for add-on install & misc utils
set -euo pipefail

# ---- Common paths (XBian) ----
KODI_USER="${KODI_USER:-xbian}"
KODI_HOME="${KODI_HOME:-/home/${KODI_USER}/.kodi}"
ADDONS_DIR="${ADDONS_DIR:-${KODI_HOME}/addons}"
PKG_DIR="${PKG_DIR:-${ADDONS_DIR}/packages}"
LOG_TAG="${LOG_TAG:-oneclick}"

umask 022
mkdir -p "$ADDONS_DIR" "$PKG_DIR" >/dev/null 2>&1 || true

log()  { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s][WARN] %s\n' "$LOG_TAG" "$*" >&2; }
die()  { printf '[%s][FATAL] %s\n' "$LOG_TAG" "$*" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

ensure_deps() {
  local miss=()
  for b in curl unzip; do has "$b" || miss+=("$b"); done
  if [ "${#miss[@]}" -gt 0 ] && has apt-get; then
    log "Installing missing tools: ${miss[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${miss[@]}" || true
  fi
  for b in curl unzip; do has "$b" || die "Required tool missing: $b"; done
}

# ---- Tiny URL fetcher for "latest" zip from a page ----
# Usage: fetch_latest_zip "https://example/releases" "repo-name-like" "/tmp/out.zip"
fetch_latest_zip() {
  ensure_deps
  local page_url="$1" match_hint="$2" out_zip="$3"
  local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"

  log "Fetching latest zip from: $page_url"
  local page
  page="$(curl -fsSL -A "$ua" "$page_url")" || { warn "curl failed: $page_url"; return 1; }

  # Find first .zip that contains match_hint (case-insensitive)
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
  ensure_deps
  local zip="$1"
  [ -f "$zip" ] || { warn "zip not found: $zip"; return 1; }

  log "Installing zip into $ADDONS_DIR: $(basename "$zip")"
  mkdir -p "$PKG_DIR"
  cp -f "$zip" "$PKG_DIR/" || true

  # Extract; top-level directory becomes addon id (repo or plugin)
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  # Unzip quietly; skip macOS cruft
  unzip -qq -o "$zip" -d "$tmpdir"
  rm -rf "$tmpdir/__MACOSX" 2>/dev/null || true

  shopt -s nullglob
  local moved=0
  for d in "$tmpdir"/*; do
    [ -d "$d" ] || continue
    local addon_id
    addon_id="$(basename "$d")"
    rm -rf  "$ADDONS_DIR/$addon_id"
    mv "$d" "$ADDONS_DIR/$addon_id"
    chown -R "${KODI_USER}:${KODI_USER}" "$ADDONS_DIR/$addon_id"
    log "Installed addon: $addon_id"
    moved=1
  done
  shopt -u nullglob
  [ "$moved" -eq 1 ] || warn "No addon directories found inside zip"

  rm -rf "$tmpdir"
  trap - EXIT
}

# ---- XBian service helpers ----
kodi_stop()    { has service && service xbmc stop    || true; }
kodi_start()   { has service && service xbmc start   || true; }
kodi_restart() { has service && service xbmc restart || true; }

# ---- Convenience: ensure a file exists with content ----
# usage: ensure_file /path/to/file "content..."
ensure_file() {
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$*" > "$f"
}
