#!/bin/bash
# STEP 2 — same as the last working v9 public release.
# Closes the disposable Zoom, deletes that profile, restores regular Zoom.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
RESOURCES="$ROOT/1132.WTF.app/Contents/Resources"
COMMON="$RESOURCES/common.sh"
RESTORE="$RESOURCES/restore_profile.sh"
SUPPORT="$HOME/Library/Application Support/1132.WTF"
STATE="$SUPPORT/active"
LOG="$HOME/Library/Logs/1132.WTF/launch.log"
mkdir -p "$(dirname "$LOG")"
printf '%s | STEP_2 | START | public_release=YES cleanup_requested=YES\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG"

if [[ ! -f "$COMMON" || ! -f "$RESTORE" ]]; then
  /usr/bin/osascript -e 'display dialog "The cleanup files are missing. Re-extract the ZIP and keep the folder together." with title "1132.WTF" buttons {"OK"} default button "OK" with icon stop' >/dev/null 2>&1 || true
  exit 66
fi

# shellcheck source=/dev/null
source "$COMMON"
if [[ -d "$STATE" ]]; then
  log_line "STEP_2" "Active disposable Zoom profile found; closing Zoom and restoring real profile"
  /bin/bash "$RESTORE" "$STATE" "step-2-manual-cleanup"
  status=$?
else
  if zoom_processes_running; then
    log_line "STEP_2" "No active disposable profile; closing currently running Zoom only"
    stop_zoom_processes || true
  fi
  log_line "STEP_2" "No active temporary profile. Nothing needed deletion or restoration"
  notify_user "1132.WTF" "Zoom is closed. No temporary profile was active, so nothing needed cleanup."
  status=0
fi
exit "$status"
