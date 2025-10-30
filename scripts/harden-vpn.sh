#!/usr/bin/env bash
set -euo pipefail
if [ -d /etc/wireguard ]; then
  chown -R root:root /etc/wireguard
  find /etc/wireguard -type f -name '*.conf' -exec chmod 600 {} \;
fi
