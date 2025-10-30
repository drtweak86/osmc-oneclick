# First Boot Hook (XBian 64-bit)

1) After flashing the image, mount the **boot** partition on your PC.
2) Copy these into the boot partition:
   - `/firstboot/firstboot.sh`  → `/boot/firstboot.sh`
   - `/systemd/oneclick-firstboot.service`  → `/etc/systemd/system/oneclick-firstboot.service`
3) Enable the unit (either now in chroot, or on-device later):
   - `ln -s /etc/systemd/system/oneclick-firstboot.service /etc/systemd/system/multi-user.target.wants/oneclick-firstboot.service`
4) Reboot. You’ll see toasts as it fetches your installer and runs it.
