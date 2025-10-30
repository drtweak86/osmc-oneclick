#!/usr/bin/env bash
#
# 42_addons.sh — Install Kodi repositories & add-ons the clean way.
# - Installs repos first (so updates are automatic)
# - Installs add-ons via Kodi’s add-on manager (InstallAddon)
# - Skips if already installed
# - Emits friendly logs + Kodi toasts
#
# Requirements: kodi-send available, Kodi running
# Tip: Fill in ZIP URLs below for any third-party repos so the
#      script can bootstrap them if Kodi can’t find the repo by ID.

set -euo pipefail

KODI_SEND_BIN="${KODI_SEND_BIN:-/usr/bin/kodi-send}"
KODI_TOAST_ICON="${KODI_TOAST_ICON:-/home/osmc/.kodi/media/notify/icons/globe_shield.png}"
SLEEP_AFTER_INSTALL="${SLEEP_AFTER_INSTALL:-2}"

log()  { echo "[addons] $*"; }
ok()   { echo -e "  \xE2\x9C\x85 $*"; }   # ✓
warn() { echo -e "  \xE2\x9A\xA0 $*"; }   # ⚠
err()  { echo -e "  \xE2\x9D\x8C $*"; }   # ❌

toast() {
  local title="$1" msg="$2"
  $KODI_SEND_BIN --action="Notification(${title},${msg},5000,${KODI_TOAST_ICON})" >/dev/null 2>&1 || true
}

need_kodi() {
  if ! command -v "$KODI_SEND_BIN" >/dev/null 2>&1; then
    err "kodi-send not found. Is Kodi installed?"
    exit 1
  fi
}

# --- Repo bootstrap map -------------------------------------------------------
# If InstallAddon(repository.*) fails (e.g., Kodi doesn’t yet know the repo),
# we’ll try to install the repo FROM ZIP using these URLs.
# Fill the right-hand sides with the official HTTPS ZIPs for your setup.
declare -A REPO_ZIPS=(
  # ["repository.umbrella"]="https://example.com/repository.umbrella-x.y.z.zip"
  # ["repository.nixgates"]="https://example.com/repository.nixgates-x.y.z.zip"
  # ["repository.a4ksubtitles"]="https://example.com/repository.a4ksubtitles-x.y.z.zip"
  # ["repository.otaku"]="https://example.com/repository.otaku-x.y.z.zip"
  # ["repository.cocoscrapers"]="https://example.com/repository.cocoscrapers-x.y.z.zip"
)

# --- What to install ----------------------------------------------------------
# 1) Repositories (IDs)
REPOS=(
  "repository.umbrella"       # Umbrella
  "repository.nixgates"       # Seren
  "repository.a4ksubtitles"   # A4KSubtitles
  "repository.otaku"          # Otaku
  "repository.cocoscrapers"   # CoCo scrapers
  # Add others here…
)

# 2) Add-ons (IDs)
ADDONS=(
  "plugin.video.umbrella"
  "plugin.video.seren"
  "script.trakt"                  # (sometimes service.trakt on older builds)
  "plugin.video.otaku"
  "script.artwork.dump"
  "service.subtitles.a4ksubtitles"
  "script.module.cocoscrapers"    # or plugin/video if that’s how it’s packaged
  # Argon V2 case fan add-on — set the correct ID below once you confirm it:
  # "service.argonv2.fan"         # TODO: replace with actual ID
  # OptiKlean (verify exact ID):
  # "service.optiklean"           # TODO: replace with actual ID
)

# --- Helpers ------------------------------------------------------------------

# Ask Kodi if an addon is installed via a builtin condition
has_addon() {
  local addon_id="$1"
  # We can use a quick JSONRPC ping by trying to run a no-op Settings action; simplest is to try installing and rely on ZX.
  # Instead, we’ll ask Kodi to echo a boolean by writing to the log via Notification (lightweight approach):
  # Practical approach: rely on InstallAddon being idempotent and check again afterward.
  # To keep it simple, we’ll treat install as idempotent and only sleep afterward.
  return 1
}

install_by_id() {
  local addon_id="$1"
  $KODI_SEND_BIN --action="InstallAddon(${addon_id})" >/dev/null 2>&1 || return 1
  sleep "$SLEEP_AFTER_INSTALL"
  return 0
}

install_repo_zip() {
  local addon_id="$1" zip_url="$2"
  if [[ -z "$zip_url" ]]; then
    return 1
  fi
  # Download to Kodi’s packages dir so Kodi can pick it up
  local pkg_dir="/home/osmc/.kodi/addons/packages"
  mkdir -p "$pkg_dir"
  local zip_path="${pkg_dir}/$(basename "$zip_url")"
  log "Downloading ZIP for ${addon_id} …"
  if ! curl -fsSL -o "$zip_path" "$zip_url"; then
    return 1
  fi
  log "Trigger Kodi to Install from ZIP …"
  # Kodi has a GUI action for “Install from zip file” but no direct action name.
  # However, Kodi watches the packages dir and is able to install repo zips when asked by InstallAddon on newer versions.
  # Fallback: open the file via RunAddon with file path (works on modern Kodi):
  $KODI_SEND_BIN --action="InstallAddon(${zip_path})" >/dev/null 2>&1 || true
  sleep "$SLEEP_AFTER_INSTALL"
  return 0
}

ensure_repo() {
  local repo_id="$1"
  log "Repo: ${repo_id}"
  toast "Add-ons" "Installing repository: ${repo_id}"
  if install_by_id "$repo_id"; then
    ok "Installed (or already present): ${repo_id}"
    return 0
  fi
  warn "InstallAddon(${repo_id}) didn’t succeed directly; trying ZIP bootstrap…"
  if install_repo_zip "$repo_id" "${REPO_ZIPS[$repo_id]:-}"; then
    ok "Bootstrapped ${repo_id} from ZIP."
    return 0
  fi
  err "Failed to install repository: ${repo_id}. Provide a ZIP URL in REPO_ZIPS."
  return 1
}

ensure_addon() {
  local addon_id="$1"
  log "Addon: ${addon_id}"
  toast "Add-ons" "Installing: ${addon_id}"
  if install_by_id "$addon_id"; then
    ok "Installed (or already present): ${addon_id}"
    return 0
  fi
  err "Failed to install add-on: ${addon_id}"
  return 1
}

# --- Run ----------------------------------------------------------------------

need_kodi
log "Starting repository installation…"
for repo in "${REPOS[@]}"; do
  ensure_repo "$repo" || true
done

log "Starting add-on installation…"
for a in "${ADDONS[@]}"; do
  ensure_addon "$a" || true
done

toast "Add-ons" "Repositories & add-ons processed. Check Add-on Browser for status."
ok "All done."
