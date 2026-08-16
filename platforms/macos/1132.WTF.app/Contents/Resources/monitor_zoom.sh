#!/bin/bash
set -u
STATE_DIR="$1"
SCRIPT_DIR="$STATE_DIR/runtime-scripts"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

log_line "MONITOR" "START cleanup_watch=ACTIVE"
SEEN=0
ABSENT_COUNT=0
START_EPOCH="$(date +%s)"

while true; do
  NOW="$(date +%s)"
  ELAPSED=$((NOW - START_EPOCH))
  if zoom_processes_running; then
    if [[ "$SEEN" -eq 0 ]]; then
      log_line "MONITOR" "Zoom process detected after=${ELAPSED}s"
    fi
    SEEN=1
    ABSENT_COUNT=0
  else
    if [[ "$SEEN" -eq 1 ]]; then
      ABSENT_COUNT=$((ABSENT_COUNT + 1))
      if [[ "$ABSENT_COUNT" -ge 5 ]]; then
        log_line "MONITOR" "Zoom fully closed; beginning automatic cleanup"
        /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$STATE_DIR" "zoom-closed"
        exit $?
      fi
    elif [[ "$ELAPSED" -ge 90 ]]; then
      log_line "MONITOR" "Zoom never appeared within 90 seconds; recovering profile"
      /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$STATE_DIR" "launch-timeout"
      exit $?
    fi
  fi
  /bin/sleep 1
done
