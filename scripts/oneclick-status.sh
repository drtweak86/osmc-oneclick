#!/usr/bin/env bash
set -euo pipefail
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[0;33m'; NC='\033[0m'
ok(){ echo -e "${GRN}OK${NC}  $*"; }
warn(){ echo -e "${YLW}WARN${NC} $*"; }
fail(){ echo -e "${RED}FAIL${NC} $*"; }

echo "== OneClick status $(date -Is) =="
echo "Host: $(hostname)  Kernel: $(uname -r)  Uptime: $(cut -d. -f1 /proc/uptime)s"
echo

if systemctl is-active --quiet mediacenter || systemctl is-active --quiet kodi || systemctl is-active --quiet xbmc; then ok "Kodi service is active"; else fail "Kodi service not active (mediacenter/kodi/xbmc)"; fi

if systemctl list-unit-files | grep -q '^oneclick-firstboot\.service'; then
  systemctl is-enabled --quiet oneclick-firstboot.service && warn "firstboot still enabled" || ok "firstboot present & disabled"
else ok "firstboot not present (already cleaned)"
fi

if systemctl list-units | grep -q 'wg-autoswitch\.service'; then
  systemctl is-active --quiet wg-autoswitch.service && ok "wg-autoswitch active" || fail "wg-autoswitch not active"
else warn "wg-autoswitch not installed"
fi

CFG_DIR="/etc/wireguard"
if [ -d "$CFG_DIR" ]; then
  shopt -s nullglob
  cfgs=("$CFG_DIR"/*.conf)
  if [ ${#cfgs[@]} -eq 0 ]; then fail "No WireGuard *.conf in $CFG_DIR"; else
    ok "Found ${#cfgs[@]} WireGuard config(s)"
    for f in "${cfgs[@]}"; do
      echo "  - $(basename "$f")"
      sed -E \
        -e 's/(PrivateKey *= *)[^# ]+/\1********/I' \
        -e 's/(PresharedKey *= *)[^# ]+/\1********/I' \
        -n 's/^\[(Interface|Peer)\].*$/\0/p; s/^(PrivateKey|PresharedKey|PublicKey|Endpoint|Address|DNS|AllowedIPs).*/\0/p' "$f" \
        | sed 's/^/      /'
    done
  fi
else fail "$CFG_DIR does not exist"
fi

bad=0
if [ -d "$CFG_DIR" ]; then
  while IFS= read -r -d '' f; do
    perms="$(stat -c '%a %U:%G' "$f")"
    [ "${perms%% *}" = "600" ] && [ "${perms#* }" = "root:root" ] || { fail "Perms $perms on $f (want 600 root:root)"; bad=1; }
  done < <(find "$CFG_DIR" -maxdepth 1 -type f -name '*.conf' -print0)
fi
[ $bad -eq 0 ] && ok "WireGuard file permissions are strict (600 root:root)"

if command -v wg >/dev/null 2>&1; then
  if wg show | grep -q '^interface:'; then ok "WireGuard interface(s) up:"; wg show | sed 's/^/  /'; else warn "No active WireGuard interfaces"; fi
else fail "wg(8) not installed"
fi

if command -v curl >/dev/null 2>&1; then
  ip="$(curl -fsS --max-time 5 https://ifconfig.io || true)"
  [ -n "${ip:-}" ] && ok "Public IP: $ip" || warn "Could not fetch public IP"
  dns="$(getent hosts example.com 2>/dev/null | awk '{print $1}' | head -n1)"
  [ -n "${dns:-}" ] && ok "DNS resolves (example.com -> $dns)" || fail "DNS lookup failed"
else warn "curl not installed; skipping IP/DNS checks"
fi
