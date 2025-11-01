#!/usr/bin/env bash
set -euo pipefail

LOG=/boot/firstboot.log
exec >>"$LOG" 2>&1
echo "=== oneclick firstboot $(date) ==="

OCROOT="/opt/osmc-oneclick"
PHASES_DIR="$OCROOT/phases"

# ---------- UI helpers ----------
_have_gui() { [[ -n "${DISPLAY:-}" ]] && command -v yad >/dev/null 2>&1; }

_spinner_start() {
  # $1 = pid to watch, $2 = label
  local pid="$1" label="${2:-Working}"
  local spin='|/-\' i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\r[%c] %s..." "${spin:$i:1}" "$label"
    sleep 0.1
  done
  printf "\r[✓] %s... done\n" "$label"
}

_gui_progress_start() {
  # start a YAD progress window reading from FIFO
  PROG_FIFO="/tmp/oneclick.progress.$$"
  mkfifo "$PROG_FIFO"

  (
    # Feed YAD the percentage and message
    while IFS=$'\t' read -r pct msg; do
      echo "$pct"
      echo "# $msg"
    done < "$PROG_FIFO"
  ) | yad --title="OSMC / XBian OneClick" \
          --center --width=600 --height=120 \
          --progress --percentage=0 --auto-close --no-buttons \
          --fixed --window-icon=system-software-install \
          --text="Preparing first boot…" >/dev/null 2>&1 &

  YAD_PID=$!
}

_gui_progress_update() {
  local pct="$1" msg="$2"
  [[ -p "${PROG_FIFO:-/dev/null}" ]] && printf "%s\t%s\n" "$pct" "$msg" >"$PROG_FIFO" || true
}

_gui_progress_end() {
  [[ -p "${PROG_FIFO:-/dev/null}" ]] && { echo "100	Finished"; rm -f "$PROG_FIFO"; }
  [[ -n "${YAD_PID:-}" ]] && kill "$YAD_PID" 2>/dev/null || true
}

# ---------- Notify Kodi if available (non-fatal) ----------
if command -d kodi-send >/dev/null 2>&1 || command -v kodi-send >/dev/null 2>&1; then
  kodi-send --action="Notification(OneClick,Running setup...,5000)" || true
fi

# ---------- Collect phases ----------
if [[ ! -d "$PHASES_DIR" ]]; then
  echo "No phases directory found at $PHASES_DIR"
  echo "firstboot done"
  exit 0
fi

mapfile -t PHASES < <(find "$PHASES_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
TOTAL=${#PHASES[@]}
if (( TOTAL == 0 )); then
  echo "No phase scripts found in $PHASES_DIR"
  echo "firstboot done"
  exit 0
fi

# ---------- Start GUI progress if possible ----------
USE_GUI=0
if _have_gui; then
  _gui_progress_start
  USE_GUI=1
fi

# ---------- Run phases with progress ----------
for idx in "${!PHASES[@]}"; do
  phase="${PHASES[$idx]}"
  base="$(basename "$phase")"
  step=$(( idx + 1 ))
  pct=$(( (step - 1) * 100 / TOTAL ))
  msg="Phase ${step}/${TOTAL}: ${base}"

  echo "--- running $base ---"

  if (( USE_GUI )); then
    _gui_progress_update "$pct" "$msg"
    # run phase and update when finished
    if bash "$phase"; then
      echo "OK: $base"
    else
      echo "WARN: phase $base returned non-zero"
    fi
  else
    # console spinner
    bash "$phase" &
    PH_PID=$!
    _spinner_start "$PH_PID" "$msg"
    wait "$PH_PID" || echo "WARN: phase $base returned non-zero"
  fi
done

# finish bar to 100
if (( USE_GUI )); then
  _gui_progress_update "100" "All phases complete"
  sleep 0.4
  _gui_progress_end
fi

echo "firstboot complete."

# Try to disable the unit (ignore if systemctl is absent on target)
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable oneclick-firstboot.service || true
fi
