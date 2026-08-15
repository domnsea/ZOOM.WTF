#!/bin/bash
#
# 1.0.20 — Open Zoom on THIS desktop.
#
# 1.0.19 created a throwaway Mac user and refused to open Zoom unless that
# other uid owned the process. macOS will not show a GUI app for a user who
# is not logged in at the window server, so STEP 1 failed and Zoom never
# appeared. That is why the Mac build did not work.
#
# This build:
#   1. kills Zoom
#   2. moves the logged-in account's Zoom identity aside
#   3. sets the Mac full name (NSFullUserName) to a random Join name
#   4. opens Zoom as the logged-in user, so a window actually appears
#   5. restores the full name and the regular Zoom profile when Zoom quits
#
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SELF="$SCRIPT_DIR/$(basename "$0")"

if [ "$(id -u)" -ne 0 ]; then
  SELF_Q="$(printf '%s' "$SELF" | sed "s/'/'\\''/g")"
  CMD="/bin/bash '$SELF_Q'"
  for a in "$@"; do
    q="$(printf '%s' "$a" | sed "s/'/'\\''/g")"
    CMD="$CMD '$q'"
  done
  /usr/bin/osascript -e "do shell script \"$(printf '%s' "$CMD" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')\" with administrator privileges"
  exit $?
fi

CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
case "$CONSOLE_USER" in
  "" | root | daemon | nobody)
    printf '%s\n' "FATAL: no console user" >&2
    exit 1
    ;;
esac
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER")"
CONSOLE_HOME="$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
[ -n "$CONSOLE_HOME" ] || CONSOLE_HOME="/Users/$CONSOLE_USER"
export HOME="$CONSOLE_HOME"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
chmod +x "$SCRIPT_DIR/"*.sh 2>/dev/null || true

log_line "LAUNCH" "START 1.0.20 console_uid=$CONSOLE_UID console_user=$CONSOLE_USER"

ZOOM_APP="$(find_zoom_app 2>/dev/null || true)"
if [[ -z "$ZOOM_APP" ]]; then
  show_dialog "1132.WTF" "Zoom is not installed in Applications. Install Zoom, then run STEP 1 again." "stop"
  exit 69
fi
ZOOM_BIN="$ZOOM_APP/Contents/MacOS/zoom.us"
if [[ ! -x "$ZOOM_BIN" ]]; then
  ZOOM_BIN="$(/usr/bin/find "$ZOOM_APP/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | /usr/bin/head -n 1)"
fi
if [[ -z "$ZOOM_BIN" || ! -x "$ZOOM_BIN" ]]; then
  show_dialog "1132.WTF" "Zoom is installed but its executable is missing. Reinstall Zoom." "stop"
  exit 69
fi

FIRSTS=(Alex Sam Jordan Casey Riley Quinn Avery Morgan Taylor Jamie Drew Reese Kai Rowan Sky Finn)
LASTS=(Chen Patel Garcia Kim Novak Silva Haddad Okafor Ivanov Dubois Rossi Nakamura Andersson Costa Weber)

name_is_login() {
  local raw lc me
  raw="$(printf '%s' "${1:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  lc="$(printf '%s' "$raw" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  me="$(printf '%s' "$CONSOLE_USER" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    "" | guest | user | root | daemon | nobody | "$me" | dustin) return 0 ;;
  esac
  return 1
}

pick_display_name() {
  local first last num full n
  n=0
  while [ "$n" -lt 8 ]; do
    first="${FIRSTS[RANDOM % ${#FIRSTS[@]}]}"
    last="${LASTS[RANDOM % ${#LASTS[@]}]}"
    num="$(printf '%03d' $((RANDOM % 1000)))"
    full="$first $last $num"
    if name_is_login "$full"; then
      n=$((n + 1))
      continue
    fi
    printf '%s\n' "$full"
    return 0
  done
  printf '%s\n' "Alex Chen 042"
}

zoom_for_uid() {
  local uid="$1"
  /usr/bin/pgrep -u "$uid" -x "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -u "$uid" -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  return 1
}

wait_for_uid_zoom() {
  local uid="$1" limit="${2:-20}" waited=0
  while [ "$waited" -lt "$limit" ]; do
    if zoom_for_uid "$uid"; then
      return 0
    fi
    /bin/sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# Run as the logged-in desktop user. GUI apps only appear for that uid.
run_on_desktop() {
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" "$@" >/dev/null 2>&1
}

open_on_desktop() {
  log_line "LAUNCH" "launchctl asuser $CONSOLE_UID sudo -u $CONSOLE_USER $*"
  run_on_desktop "$@" &
}

seed_join_name() {
  local name="$1"
  run_on_desktop /usr/bin/defaults write us.zoom.xos ZoomUserName "$name" || true
  run_on_desktop /usr/bin/defaults write zoom.us ZoomUserName "$name" || true
  /bin/mkdir -p "$CONSOLE_HOME/Library/Application Support/zoom.us/data"
  printf '[General]\nnUsername=%s\n' "$name" >"$CONSOLE_HOME/Library/Application Support/zoom.us/data/zoomus.ini"
  /usr/sbin/chown -R "$CONSOLE_USER:staff" "$CONSOLE_HOME/Library/Application Support/zoom.us" >/dev/null 2>&1 || true
  log_line "LAUNCH" "SEEDED join name=$name"
}

if [ "${1:-}" = "--watch" ]; then
  STATE_DIR="${2:-$ACTIVE_STATE}"
  log_line "WATCH" "waiting for desktop Zoom to quit"
  appeared=0
  waited=0
  while [ "$waited" -lt 180 ]; do
    if zoom_for_uid "$CONSOLE_UID"; then
      appeared=1
      break
    fi
    /bin/sleep 1
    waited=$((waited + 1))
  done
  if [ "$appeared" -eq 1 ]; then
    while zoom_for_uid "$CONSOLE_UID"; do
      /bin/sleep 2
    done
  fi
  /usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
  if [ -x "$SCRIPT_DIR/1132wtf-setname.sh" ]; then
    /bin/bash "$SCRIPT_DIR/1132wtf-setname.sh" --restore >/dev/null 2>&1 || true
  fi
  export HOME="$CONSOLE_HOME"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$STATE_DIR" "zoom-closed" || true
  log_line "WATCH" "DONE full name and regular Zoom profile restored"
  exit 0
fi

REQUESTED_NAME="$(printf '%s' "${1:-}" | /usr/bin/tr -cd 'A-Za-z0-9 ._-')"

/usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
/usr/bin/pkill -9 -f "/zoom.us.app/" >/dev/null 2>&1 || true
/bin/sleep 1

if [[ -d "$ACTIVE_STATE" ]]; then
  log_line "LAUNCH" "RECOVERY leftover session"
  leftover="$(/usr/bin/tr -d '\r\n' <"$ACTIVE_STATE/temp.user" 2>/dev/null || true)"
  case "$leftover" in
    "" | "$CONSOLE_USER" | root | daemon | nobody) ;;
    *)
      /usr/sbin/sysadminctl -deleteUser "$leftover" >/dev/null 2>&1 || true
      /bin/rm -rf "/Users/$leftover" >/dev/null 2>&1 || true
      ;;
  esac
  if [ -x "$SCRIPT_DIR/1132wtf-setname.sh" ]; then
    /bin/bash "$SCRIPT_DIR/1132wtf-setname.sh" --restore >/dev/null 2>&1 || true
  fi
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "startup-recovery" || true
fi

if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
  show_dialog "1132.WTF" "Another 1132.WTF launch is still active. Quit Zoom, wait a few seconds, then run STEP 1 again." "stop"
  exit 75
fi

/bin/mkdir -p "$ACTIVE_STATE/backup" "$ACTIVE_STATE/runtime-home" "$ACTIVE_STATE/runtime-scripts"
/bin/chmod 700 "$ACTIVE_STATE" "$ACTIVE_STATE/backup" "$ACTIVE_STATE/runtime-home"
/bin/cp "$SCRIPT_DIR/common.sh" "$ACTIVE_STATE/runtime-scripts/common.sh"
/bin/cp "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE/runtime-scripts/restore_profile.sh"
/bin/chmod 700 "$ACTIVE_STATE/runtime-scripts/"*.sh

TARGETS_FILE="$ACTIVE_STATE/targets.txt"
MANIFEST="$ACTIVE_STATE/original-manifest.txt"
: > "$MANIFEST"
collect_zoom_targets "$TARGETS_FILE"
kill_preferences_cache
MOVED=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  source_path="$CONSOLE_HOME/$rel"
  backup_path="$ACTIVE_STATE/backup/$rel"
  if [[ -e "$source_path" || -L "$source_path" ]]; then
    /bin/mkdir -p "$(dirname "$backup_path")"
    if /bin/mv "$source_path" "$backup_path" 2>/dev/null; then
      printf '%s\n' "$rel" >> "$MANIFEST"
      MOVED=$((MOVED + 1))
    fi
  fi
done < "$TARGETS_FILE"
kill_preferences_cache
log_line "LAUNCH" "PROFILE_READY protected_items=$MOVED"

DISPLAY_NAME="$(pick_display_name)"
if ! name_is_login "$REQUESTED_NAME"; then
  DISPLAY_NAME="$REQUESTED_NAME"
fi
printf '%s\n' "$DISPLAY_NAME" >"$ACTIVE_STATE/display.name"
printf '%s\n' "$DISPLAY_NAME" >"$LOG_DIR/last_display_name.txt"
log_line "LAUNCH" "JOIN_NAME display=$DISPLAY_NAME"

if [ -x "$SCRIPT_DIR/1132wtf-setname.sh" ]; then
  if /bin/bash "$SCRIPT_DIR/1132wtf-setname.sh" --start-from "$ACTIVE_STATE"; then
    log_line "LAUNCH" "RealName set to $DISPLAY_NAME"
  else
    log_line "LAUNCH" "WARN RealName helper failed; Zoom still opens"
  fi
fi
seed_join_name "$DISPLAY_NAME"
/usr/bin/killall cfprefsd >/dev/null 2>&1 || true
/bin/sleep 1

open_on_desktop /usr/bin/open -a "$ZOOM_APP"
if ! wait_for_uid_zoom "$CONSOLE_UID" 12; then
  log_line "LAUNCH" "retry Zoom binary on the desktop"
  open_on_desktop "$ZOOM_BIN"
  wait_for_uid_zoom "$CONSOLE_UID" 10 || true
fi

if ! zoom_for_uid "$CONSOLE_UID"; then
  log_line "LAUNCH" "FAILED Zoom window did not appear on the logged-in desktop"
  if [ -x "$SCRIPT_DIR/1132wtf-setname.sh" ]; then
    /bin/bash "$SCRIPT_DIR/1132wtf-setname.sh" --restore >/dev/null 2>&1 || true
  fi
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "launch-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  show_dialog "1132.WTF" "Zoom did not open on this desktop. Install Zoom in Applications, then run STEP 1 again." "stop"
  exit 72
fi

log_line "LAUNCH" "OK Zoom is open on this desktop as $DISPLAY_NAME"
/usr/bin/nohup /bin/bash "$SELF" --watch "$ACTIVE_STATE" >>"$LOG_FILE" 2>&1 &
printf '%s\n' "$!" >"$ACTIVE_STATE/monitor.pid"
printf '%s' "$DISPLAY_NAME" | /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/pbcopy >/dev/null 2>&1 || true
notify_user "1132.WTF" "Fresh Zoom is opening as $DISPLAY_NAME"
show_dialog "1132.WTF" "Fresh Zoom is open as:

$DISPLAY_NAME

That is the name Join should show. Do not sign in as the old Zoom account.

When you quit Zoom, your Mac full name and regular Zoom profile are restored." "note"
exit 0
