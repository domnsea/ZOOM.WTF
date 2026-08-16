#!/bin/bash
# STEP 1 — wipe Zoom identity, set a random Join name, open Zoom here.
# Password once. Zoom must appear on this desktop.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
LAUNCH="$ROOT/1132.WTF.app/Contents/Resources/launch_fresh_zoom.sh"
LOG="$HOME/Library/Logs/1132.WTF/launch.log"
mkdir -p "$(dirname "$LOG")"
printf '%s | STEP_1 | START | public_release=YES same_desktop=YES version=1.0.20\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG"
if [[ ! -f "$LAUNCH" ]]; then
  /usr/bin/osascript -e 'display dialog "launch_fresh_zoom.sh is missing. Re-extract the ZIP and keep the folder together." with title "1132.WTF" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1 || true
  exit 66
fi
/bin/chmod -R u+rwX "$ROOT/1132.WTF.app" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.quarantine "$ROOT/1132.WTF.app" 2>/dev/null || true
exec /bin/bash "$LAUNCH"
