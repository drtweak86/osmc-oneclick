#!/usr/bin/env bash
set -euo pipefail
prefix="[oneclick][35_argon_fan]"
say(){ echo "$prefix $*"; }

say "Applying Argon fan preset (Balanced Mode)"

cat <<'EOF' >/etc/argononed.conf
50=25
60=60
70=100
EOF

say "Restarting argononed service"
systemctl restart argononed.service || true
say "Argon fan config applied."
