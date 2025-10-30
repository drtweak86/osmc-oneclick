# 🦈 OneClick XBian — Pi Media Perfection 🎬  
*Fully-automated Raspberry Pi 4 64-bit media setup for Kodi 21 (Omega)*  

---

## 🚀 What It Does
Transform a fresh **XBian 64-bit** install into a complete, self-tuning media system —  
optimized for **streaming, stability, and automation**.

✅ **Performance**
- Safe Pi 4B overclock + GPU memory tuning  
- Network stack optimization (BBR, DNS cache, entropy fix)  
- Argon One V2 fan + power daemon with smart temperature curves  

✅ **Smart Networking**
- 🔄 VPN auto-switcher — measures throughput / latency and picks the fastest tunnel  
- 📶 Wi-Fi auto-switcher — automatically connects to the strongest SSID for smooth streaming  
  *(pre-set for `Batcave` and `🐢` networks)*  
- ⚡ Built-in `speedtest` CLI integration for quick benchmarking  

✅ **Kodi & Streaming**
- Arctic Fuse 2 skin + EXO2 font family  
- Installs and updates key add-ons automatically:  
  - **Umbrella**, **Seren**, **A4KSubs**, **OptiKlean**, **CocoScrapers**, **Otaku**, **Trakt**, **Artwork Dump**, **BBviking patch**  
- 🎚 Automatic QoL tuning on first boot:  
  - Refresh-rate switching = On Start/Stop  
  - HQ scalers = 10 %  
  - Sync to display = off  
  - Audio passthrough = auto-detect (🎧 Hisense AX3120G tested)  

✅ **Automation**
- 🗓 Weekly maintenance & system cleanup  
- ☁️ Nightly rclone backups to Google Drive (keeps 3 latest archives)  
- 🧩 Self-healing installer — fetches missing phases from GitHub  

---

## 🧰 Installation on XBian 64-bit

### 1️⃣ Prepare the System
Flash the latest **XBian 64-bit for Raspberry Pi 4B** image to your SD card.  
Boot it, connect to the network, and SSH in:

```bash
ssh xbian@<pi-ip-address>
# default password: raspberry
