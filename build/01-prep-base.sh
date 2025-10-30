#!/usr/bin/env bash
set -euo pipefail

usage(){ echo "Usage: $0 --base <img|img.gz> --workdir <path>"; exit 1; }
BASE=""; WORKDIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "${BASE:-}" && -n "${WORKDIR:-}" ]] || usage

mkdir -p "$WORKDIR"
BASE_ABS="$(readlink -f "$BASE")" || { echo "Base not found: $BASE" >&2; exit 1; }

# Prepare base.img in WORKDIR
if [[ "$BASE_ABS" == *.gz ]]; then
  cp -f "$BASE_ABS" "$WORKDIR/base.img.gz"
  gunzip -f "$WORKDIR/base.img.gz"
  BASE_PATH="$WORKDIR/base.img"
else
  cp -f "$BASE_ABS" "$WORKDIR/base.img"
  BASE_PATH="$WORKDIR/base.img"
fi

[[ -f "$BASE_PATH" ]] || { echo "Failed to prepare base at $BASE_PATH" >&2; exit 1; }

# Persist for later stages
echo "$BASE_PATH" > "$WORKDIR/base.path"
echo "BASE_PATH=$BASE_PATH"
