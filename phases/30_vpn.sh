#!/usr/bin/env bash
set -euo pipefail

# WireGuard skeleton; drops a systemd unit that auto-starts when config exists
apt-get install -y --no-install-recommends wireguard-tools

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# If a wg config is already present (you can upload later), enable it
if ls /etc/wireguard/*.conf >/dev/null 2>&1; then
  systemctl enable --now wg-quick@$(basename /etc/wireguard/*.conf .conf)
fi

# Placeholder for “auto-switch based on throughput/latency” (future module)
install -d /opt/osmc-oneclick/vpn
cat >/opt/osmc-oneclick/vpn/README.md <<'EOT'
Drop your WireGuard config at /etc/wireguard/<name>.conf then:
  sudo systemctl enable --now wg-quick@<name>
Auto-switcher will be added here later.
EOT
