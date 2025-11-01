toast_notify() {
  # deps: curl (for JSON-RPC fallback)
  local country="${1:-gb}"
  local label="${2:-VPN}"
  local name="${3:-Connected}"
  local mbps="${4:-0}"

  # Use KODI_HOME from helpers (defaults to /home/xbian/.kodi)
  local kodi_home="${KODI_HOME:-/home/xbian/.kodi}"
  local flag_img="${kodi_home}/media/notify/flags/${country}.png"
  [ -f "$flag_img" ] || flag_img="${kodi_home}/media/notify/flags/default.png"

  # Build message; escape commas for kodi-send parsing
  local text="🦈 ${label} ${name} ${mbps}Mbps"
  local text_esc="${text//,/\\,}"

  if command -v kodi-send >/dev/null 2>&1; then
    kodi-send --action="Notification(VPN Switch,${text_esc},5000,${flag_img})" >/dev/null 2>&1 || true
    return 0
  fi

  # Fallback: Kodi JSON-RPC (assumes Web server enabled on 127.0.0.1:8080)
  if command -v curl >/dev/null 2>&1; then
    local rpc='{"jsonrpc":"2.0","id":1,"method":"GUI.ShowNotification","params":{"title":"VPN Switch","message":'"$(printf '%s' "$text" | jq -R .)"',"image":'"$(printf '%s' "$flag_img" | jq -R .)"',"displaytime":5000}}'
    # If you need auth, export KODI_RPC_AUTH="user:pass"
    if [ -n "${KODI_RPC_AUTH:-}" ]; then
      curl -fsS --max-time 1 -u "$KODI_RPC_AUTH" -H 'Content-Type: application/json' \
        -d "$rpc" http://127.0.0.1:8080/jsonrpc >/dev/null 2>&1 || true
    else
      curl -fsS --max-time 1 -H 'Content-Type: application/json' \
        -d "$rpc" http://127.0.0.1:8080/jsonrpc >/dev/null 2>&1 || true
    fi
    return 0
  fi

  # Last resort: log to stdout
  echo "[toast] ${text}"
}
