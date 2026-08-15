#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

log_line "LAUNCH_V9" "START public_release=YES same_desktop=YES macOS=$(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)"

ZOOM_APP="$(find_zoom_app 2>/dev/null || true)"
if [[ -z "$ZOOM_APP" ]]; then
  log_line "LAUNCH_V9" "FAILED Zoom app not found"
  show_dialog "1132.WTF" "Zoom Workplace is not installed in Applications. Install Zoom first, then open 1132.WTF again." "stop"
  /usr/bin/open "https://zoom.us/download" >/dev/null 2>&1 || true
  exit 69
fi

ZOOM_BIN="$ZOOM_APP/Contents/MacOS/zoom.us"
if [[ ! -x "$ZOOM_BIN" ]]; then
  ZOOM_BIN="$(/usr/bin/find "$ZOOM_APP/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | /usr/bin/head -n 1)"
fi
if [[ -z "$ZOOM_BIN" || ! -x "$ZOOM_BIN" ]]; then
  log_line "LAUNCH_V9" "FAILED Zoom executable missing or damaged"
  show_dialog "1132.WTF" "The Zoom application was found, but its executable is missing or damaged. Reinstall Zoom Workplace." "stop"
  exit 69
fi

# Recover automatically if a previous run was interrupted by restart, force quit, or power loss.
if [[ -d "$ACTIVE_STATE" ]]; then
  log_line "LAUNCH_V9" "RECOVERY previous active state detected"
  if ! /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "startup-recovery"; then
    exit 74
  fi
fi

if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
  log_line "LAUNCH_V9" "FAILED another launcher or cleanup owns the lock"
  show_dialog "1132.WTF" "Another 1132.WTF launch or cleanup is still active. Close Zoom completely, wait a few seconds, then open 1132.WTF again." "stop"
  exit 75
fi

cleanup_lock_on_failure() {
  status=$?
  if [[ "$status" -ne 0 && ! -d "$ACTIVE_STATE" ]]; then
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup_lock_on_failure EXIT

if zoom_processes_running; then
  log_line "LAUNCH_V9" "Existing Zoom detected; closing it before profile swap"
  if ! stop_zoom_processes; then
    show_dialog "1132.WTF" "Zoom is still running and the profile cannot be switched safely. Close Zoom completely, then open 1132.WTF again." "stop"
    /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
    exit 70
  fi
fi

/bin/mkdir -p "$ACTIVE_STATE/backup" "$ACTIVE_STATE/runtime-home/Library" "$ACTIVE_STATE/runtime-tmp" "$ACTIVE_STATE/runtime-scripts"
/bin/chmod 700 "$ACTIVE_STATE" "$ACTIVE_STATE/backup" "$ACTIVE_STATE/runtime-home" "$ACTIVE_STATE/runtime-tmp"

/bin/cp "$SCRIPT_DIR/common.sh" "$ACTIVE_STATE/runtime-scripts/common.sh"
/bin/cp "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE/runtime-scripts/restore_profile.sh"
/bin/cp "$SCRIPT_DIR/monitor_zoom.sh" "$ACTIVE_STATE/runtime-scripts/monitor_zoom.sh"
/bin/chmod 700 "$ACTIVE_STATE/runtime-scripts/"*.sh

TARGETS_FILE="$ACTIVE_STATE/targets.txt"
MANIFEST="$ACTIVE_STATE/original-manifest.txt"
: > "$MANIFEST"
collect_zoom_targets "$TARGETS_FILE"

cat > "$ACTIVE_STATE/run-receipt.txt" <<RECEIPT
1132.WTF PUBLIC RELEASE - SAME-DESKTOP FRESH ZOOM RECEIPT
Started: $(date '+%Y-%m-%d %H:%M:%S')
macOS: $(/usr/bin/sw_vers -productVersion 2>/dev/null || echo unknown)
Identity collection: disabled
Zoom location logging: disabled
Temporary profile: active and privately managed
Regular Zoom profile: protected in private backup
Log: ~/Library/Logs/1132.WTF/launch.log
RECEIPT

kill_preferences_cache
MOVED=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  source_path="$HOME/$rel"
  backup_path="$ACTIVE_STATE/backup/$rel"
  if [[ -e "$source_path" || -L "$source_path" ]]; then
    /bin/mkdir -p "$(dirname "$backup_path")"
    if /bin/mv "$source_path" "$backup_path" 2>/dev/null; then
      printf '%s\n' "$rel" >> "$MANIFEST"
      MOVED=$((MOVED + 1))
      log_line "LAUNCH_V9" "BACKED_UP path=$rel"
    else
      log_line "LAUNCH_V9" "FAILED backing up path=$rel"
      /bin/bash "$ACTIVE_STATE/runtime-scripts/restore_profile.sh" "$ACTIVE_STATE" "backup-failure" || true
      show_dialog "1132.WTF" "The regular Zoom profile could not be protected safely. Nothing new was launched. Open OPEN_LOGS.command for the failure receipt." "stop"
      exit 73
    fi
  fi
done < "$TARGETS_FILE"

kill_preferences_cache
log_line "LAUNCH_V9" "PROFILE_READY protected_items=$MOVED disposable_environment=READY"

if [[ -z "${WTF1132_DISPLAY_NAME:-}" ]]; then
  FIRSTS=(Alex Sam Jordan Casey Riley Quinn Avery Morgan Taylor Jamie Drew Reese Kai Rowan Sky Finn)
  LASTS=(Chen Patel Garcia Kim Novak Silva Haddad Okafor Ivanov Dubois Rossi Nakamura Andersson Costa Weber)
  WTF1132_DISPLAY_NAME="${FIRSTS[RANDOM % ${#FIRSTS[@]}]} ${LASTS[RANDOM % ${#LASTS[@]}]} $(printf '%03d' $((RANDOM % 1000)))"
  export WTF1132_DISPLAY_NAME
fi
printf '%s\n' "$WTF1132_DISPLAY_NAME" > "$LOG_DIR/last_display_name.txt"

# Monitor is detached so cleanup still runs if the launcher app closes.
/usr/bin/nohup /bin/bash "$ACTIVE_STATE/runtime-scripts/monitor_zoom.sh" "$ACTIVE_STATE" >> "$LOG_FILE" 2>&1 </dev/null &
MONITOR_PID=$!
printf '%s\n' "$MONITOR_PID" > "$ACTIVE_STATE/monitor.pid"
log_line "LAUNCH_V9" "MONITOR_STARTED cleanup_watch=ACTIVE"

# CFFIXED_USER_HOME and HOME create a disposable per-launch environment while the real Zoom profile is also physically protected.
TEMP_HOME="$ACTIVE_STATE/runtime-home"
TEMP_TMP="$ACTIVE_STATE/runtime-tmp/"
DISPLAY_NAME="${WTF1132_DISPLAY_NAME:-}"
/usr/bin/nohup /usr/bin/env \
  HOME="$TEMP_HOME" \
  CFFIXED_USER_HOME="$TEMP_HOME" \
  TMPDIR="$TEMP_TMP" \
  CFPREFERENCES_AVOID_DAEMON=1 \
  USER="$(id -un)" \
  LOGNAME="$(id -un)" \
  "$ZOOM_BIN" >/dev/null 2>&1 </dev/null &
ZOOM_START_PID=$!
printf '%s\n' "$ZOOM_START_PID" > "$ACTIVE_STATE/zoom-start.pid"
log_line "LAUNCH_V9" "ZOOM_STARTED disposable_profile=YES console_capture=DISABLED"

/bin/sleep 2
if [[ -n "$DISPLAY_NAME" ]]; then
  notify_user "1132.WTF" "Fresh Zoom is opening. Type this name in Zoom Join: $DISPLAY_NAME"
else
  notify_user "1132.WTF" "Fresh Zoom is opening on this desktop. Close Zoom completely to erase the temporary profile and restore your regular one."
fi
exit 0
