toast_notify() {
  local flag_img="$HOME/.kodi/media/notify/flags/$1.png"
  local text="🦈 $2 $3 ${4}Mbps"
  if [ -x /usr/bin/kodi-send ]; then
    /usr/bin/kodi-send --action="Notification(VPN Switch,${text},5000,${flag_img})" >/dev/null 2>&1
  else
    echo "[toast] ${text}"
  fi
}
