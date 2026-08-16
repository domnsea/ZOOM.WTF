#!/bin/bash
# STEP 1 — open Zoom on this desktop with a blank profile.
# Password once. Old Zoom settings are moved aside for this session.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
LAUNCH="$ROOT/1132.WTF.app/Contents/Resources/launch_fresh_zoom.sh"
LOG="$HOME/Library/Logs/1132.WTF/launch.log"
mkdir -p "$(dirname "$LOG")"
printf '%s | STEP_1 | START | public_release=YES same_desktop=YES blank_profile=YES\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG"
if [[ ! -f "$LAUNCH" ]]; then
  printf '%s\n' "launch_fresh_zoom.sh is missing. Re-extract the ZIP and keep the folder together."
  exit 66
fi
/bin/chmod -R u+rwX "$ROOT/1132.WTF.app" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.quarantine "$ROOT/1132.WTF.app" 2>/dev/null || true
exec /bin/bash "$LAUNCH"
