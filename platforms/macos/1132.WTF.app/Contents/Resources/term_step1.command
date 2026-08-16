#!/bin/bash
# Opened in Terminal by the app. No osascript.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"
printf '%s\n' "1132 FRESH — STEP 1 - Fix Zoom"
exec /bin/bash "$HERE/launch_fresh_zoom.sh"
