#!/bin/bash
set -euxo pipefail

mkdir -p tmp-build tmp-mnt/{boot,root}

# Prefer an existing base image or extract from latest oneclick zip
if [ ! -f base-xbian.img ]; then
  unzip -p oneclick_*.zip base-xbian.img > tmp-build/xbian-oneclick.img
else
  cp -f base-xbian.img tmp-build/xbian-oneclick.img
fi

IMG="$PWD/tmp-build/xbian-oneclick.img"
LOOP="$(sudo losetup -fP --show "$IMG")"
echo "Loop device: $LOOP"

sudo mount ${LOOP}p1 tmp-mnt/boot
sudo mount ${LOOP}p2 tmp-mnt/root

# Inject oneclick payload
sudo install -d -m 0755 tmp-mnt/root/opt/osmc-oneclick/{phases,assets}
sudo rsync -a --delete ./phases/ tmp-mnt/root/opt/osmc-oneclick/phases/
sudo rsync -a --delete ./assets/ tmp-mnt/root/opt/osmc-oneclick/assets/

# Defaults
[ -f assets/config/wifi-autoswitch ] && sudo install -m 0644 assets/config/wifi-autoswitch tmp-mnt/root/etc/default/wifi-autoswitch || true
[ -f assets/config/wg-autoswitch   ] && sudo install -m 0644 assets/config/wg-autoswitch   tmp-mnt/root/etc/default/wg-autoswitch   || true

# Firstboot script
sudo tee tmp-mnt/boot/firstboot.sh >/dev/null <<'EOT'
#!/bin/bash
set -euo pipefail
LOG=/var/log/oneclick-firstboot.log
exec >>"$LOG" 2>&1
echo "=== OneClick First Boot $(date) ==="
BASE="/opt/osmc-oneclick"; PHASES="$BASE/phases"
toast(){ command -v kodi-send >/dev/null 2>&1 && kodi-send --action="Notification(OneClick,$1,5000)" || true; }
if [ -d "$PHASES" ]; then
  for s in "$PHASES"/*.sh; do [ -x "$s" ] || continue; echo "[*] Running $(basename "$s")"; toast "$(basename "$s")"; "$s"; done
fi
systemctl disable --now oneclick-firstboot.service || true
rm -f /boot/firstboot.sh || true
echo "=== OneClick done ==="
EOT
sudo chmod +x tmp-mnt/boot/firstboot.sh

# systemd service
sudo tee tmp-mnt/root/etc/systemd/system/oneclick-firstboot.service >/dev/null <<'EOT'
[Unit]
Description=OneClick First Boot (Inject Phases)
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target
ConditionPathExists=/boot/firstboot.sh

[Service]
Type=oneshot
ExecStart=/bin/bash -e /boot/firstboot.sh
StandardOutput=journal+console
StandardError=inherit

[Install]
WantedBy=multi-user.target
EOT

sudo install -d tmp-mnt/root/etc/systemd/system/multi-user.target.wants
sudo ln -sf ../oneclick-firstboot.service tmp-mnt/root/etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service

# Append include to /boot/config.txt if missing
if ! grep -q "config\.txt\.d/\*\.conf" tmp-mnt/boot/config.txt 2>/dev/null; then
  echo -e "\n[all]\ninclude config.txt.d/*.conf" | sudo tee -a tmp-mnt/boot/config.txt >/dev/null
  sudo install -d tmp-mnt/boot/config.txt.d
fi

sync
sudo umount tmp-mnt/boot tmp-mnt/root
sudo losetup -d "$LOOP"

bash ./verify-oneclick-image.sh "$IMG"
