#!/usr/bin/env bash
set -euo pipefail
fail=0
for f in \
  firstboot/firstboot.sh \
  systemd/oneclick-firstboot.service \
  assets/config/wifi-autoswitch \
  phases/04_prereqs.sh \
  install.sh
do
  [ -f "$f" ] || { echo "MISSING: $f"; fail=1; }
done
[ $fail -eq 0 ] && echo "Repo sanity OK" || exit 1
