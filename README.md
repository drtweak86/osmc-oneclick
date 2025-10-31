⚡ Xtreme v1.0 — The Beginning of Domination ⚡

A Bat-Net Production — Powered by XBian


---

🎯 Overview

The first stable public build of the Xtreme Image Builder.
A fully automated, two-stage installer that merges the clean simplicity of XBian
with Bat-Net’s encrypted, optimised, and self-healing workflow.


---

🚀 What’s New

✅ Two-Stage Boot Flow

Stage 1: Shows XBian wizard, lets the user set up Wi-Fi and system basics.

Stage 2: After reboot, automatically configures network, VPN, and system optimisations.


✅ Automatic Dependency Checks
Installer confirms all required packages (pv, gzip, util-linux, etc.) before running.

✅ Progress Bar + Flash Prompt
End-to-end image build with live compression and SD-card flashing prompt.

✅ SHA256 Verification
Image integrity checked automatically after compression.

✅ Self-Cleaning Build Process
Temporary mounts and loop devices are automatically detached. No junk left behind.


---

🧩 Build Instructions

cd ~/osmc-oneclick
git pull origin main
chmod +x build-oneclick-image.sh
sudo ./build-oneclick-image.sh XBian_Latest_arm64_rpi5.img Xtreme_v1.0.img

You’ll end up with:

Xtreme_v1.0.img.gz
Xtreme_v1.0.img.gz.sha256


---

💾 Flash to SD Card

When prompted:

Would you like to flash it to SD now? [y/N]

Type Y and let the magic happen.
Progress bar = live write speed and completion indicator.
Device used: /dev/mmcblk0 (auto-detected).


---

🧙 First Boot Flow

Boot	What Happens	Visual

1st Boot	XBian wizard launches. A toast message reminds you to finish setup and reboot.	🧩 “Configure network… then reboot.”
2nd Boot	Stage 2 scripts run silently, apply your VPN + optimisation stack, then toast success.	⚙️ “Optimisations complete. Enjoy!”



---

🔍 Verification (optional)

To double-check integrity:

sudo ./verify-oneclick-image.sh Xtreme_v1.0.img.gz Xtreme_v1.0.img.gz.sha256

To view Stage 2 logs after first real boot:

journalctl -u oneclick-stage2.service


---

🧰 For Developers

Everything lives under:

/opt/osmc-oneclick/
  ├── scripts/
  │    ├── oneclick-stage1.sh
  │    └── oneclick-stage2.sh
  └── systemd units in /etc/systemd/system/

/var/lib/oneclick/ holds the tiny flag files:

wizard-gate.shown
done


---

🧠 Next Up — Xtreme v1.2 (Codename: “The Loopback”)

Plans are brewing to make v1.2 smarter:

Self-rebuilding OTA updates (loop-mounted upgrades)

On-device re-bake for new releases

Integrated network recovery wizard

Possibly… first steps toward the “autonomous boot agent”



---

💬 Credits

Jordan H. — Chief Chaos Engineer

ChatGPT (GPT-5) — Dev Assistant, sanity-checker, and occasional sausage



---
