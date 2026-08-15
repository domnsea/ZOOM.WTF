#!/bin/bash
#
# One password. Open Zoom as a throwaway Mac user whose short name is
# not the logged-in account. If Zoom is still the login account, fail.
# Do not fall back to opening Zoom as the Mac login — that is why Join
# kept showing dustin.
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

log_line "LAUNCH" "START console_uid=$CONSOLE_UID"

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

pick_identity() {
  local first last num short full n
  n=0
  while [ "$n" -lt 8 ]; do
    first="${FIRSTS[RANDOM % ${#FIRSTS[@]}]}"
    last="${LASTS[RANDOM % ${#LASTS[@]}]}"
    num="$(printf '%03d' $((RANDOM % 1000)))"
    short="$(printf '%s%s%s' "$first" "$last" "$num" | /usr/bin/tr '[:upper:]' '[:lower:]')"
    full="$first $last $num"
    if name_is_login "$short" || name_is_login "$full"; then
      n=$((n + 1))
      continue
    fi
    if /usr/bin/dscl . -read "/Users/$short" >/dev/null 2>&1; then
      n=$((n + 1))
      continue
    fi
    printf '%s\t%s\n' "$short" "$full"
    return 0
  done
  return 1
}

delete_temp_user() {
  local user="$1"
  case "$user" in
    "$CONSOLE_USER" | root | daemon | nobody | "" ) return 0 ;;
  esac
  if /usr/bin/dscl . -read "/Users/$user" >/dev/null 2>&1; then
    /usr/sbin/sysadminctl -deleteUser "$user" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "/Users/$user" >/dev/null 2>&1 || true
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

kill_login_zoom() {
  if zoom_for_uid "$CONSOLE_UID"; then
    log_line "LAUNCH" "KILL login-account Zoom so it cannot show the Mac login name"
    /usr/bin/pgrep -u "$CONSOLE_UID" -x "zoom.us" | while read -r pid; do
      /bin/kill -9 "$pid" 2>/dev/null || true
    done
    /usr/bin/pgrep -u "$CONSOLE_UID" -f "zoom.us.app/Contents/MacOS" | while read -r pid; do
      /bin/kill -9 "$pid" 2>/dev/null || true
    done
  fi
}

if [ "${1:-}" = "--watch" ]; then
  STATE_DIR="${2:-$ACTIVE_STATE}"
  TEMP_USER="${3:-}"
  TEMP_UID="${4:-}"
  log_line "WATCH" "waiting for throwaway Zoom to quit"
  appeared=0
  waited=0
  while [ "$waited" -lt 180 ]; do
    if [ -n "$TEMP_UID" ] && zoom_for_uid "$TEMP_UID"; then
      appeared=1
      break
    fi
    /bin/sleep 1
    waited=$((waited + 1))
  done
  if [ "$appeared" -eq 1 ]; then
    while zoom_for_uid "$TEMP_UID"; do
      /bin/sleep 2
    done
  fi
  /usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
  [ -n "$TEMP_USER" ] && delete_temp_user "$TEMP_USER"
  export HOME="$CONSOLE_HOME"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$STATE_DIR" "zoom-closed" || true
  log_line "WATCH" "DONE throwaway user removed and regular profile restored"
  exit 0
fi

REQUESTED_NAME="$(printf '%s' "${1:-}" | /usr/bin/tr -cd 'A-Za-z0-9 ._-')"

/usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
/usr/bin/pkill -9 -f "/zoom.us.app/" >/dev/null 2>&1 || true
/bin/sleep 1

if [[ -d "$ACTIVE_STATE" ]]; then
  log_line "LAUNCH" "RECOVERY leftover session"
  leftover="$(/usr/bin/tr -d '\r\n' <"$ACTIVE_STATE/temp.user" 2>/dev/null || true)"
  [ -n "$leftover" ] && delete_temp_user "$leftover"
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

IDENT="$(pick_identity)" || {
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "identity-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  show_dialog "1132.WTF" "Could not create a throwaway Zoom user. Regular Zoom was left in place." "stop"
  exit 71
}
TEMP_USER="$(printf '%s\n' "$IDENT" | /usr/bin/awk -F'\t' '{print $1}')"
DISPLAY_NAME="$(printf '%s\n' "$IDENT" | /usr/bin/awk -F'\t' '{print $2}')"
if ! name_is_login "$REQUESTED_NAME"; then
  DISPLAY_NAME="$REQUESTED_NAME"
fi
PASSWORD="$(/usr/bin/openssl rand -base64 24 | /usr/bin/tr -d '/+=' | /usr/bin/head -c 20)"

if ! /usr/sbin/sysadminctl -addUser "$TEMP_USER" -fullName "$DISPLAY_NAME" -password "$PASSWORD" >/dev/null 2>&1; then
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "adduser-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  show_dialog "1132.WTF" "Could not create a throwaway Zoom user. Regular Zoom was left in place." "stop"
  exit 71
fi
/usr/bin/dscl . -create "/Users/$TEMP_USER" IsHidden 1 >/dev/null 2>&1 || true
/usr/bin/dscl . -create "/Users/$TEMP_USER" RealName "$DISPLAY_NAME" >/dev/null 2>&1 || true
/usr/bin/dscl . -create "/Users/$TEMP_USER" UserShell /bin/bash >/dev/null 2>&1 || true
/usr/sbin/createhomedir -c -u "$TEMP_USER" >/dev/null 2>&1 || true
TEMP_HOME="$(/usr/bin/dscl . -read "/Users/$TEMP_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
[ -n "$TEMP_HOME" ] || TEMP_HOME="/Users/$TEMP_USER"
/bin/mkdir -p \
  "$TEMP_HOME/tmp" \
  "$TEMP_HOME/Library/Application Support" \
  "$TEMP_HOME/Library/Preferences" \
  "$TEMP_HOME/Library/Caches" \
  "$TEMP_HOME/Library/Logs"
/usr/sbin/chown -R "$TEMP_USER:staff" "$TEMP_HOME" >/dev/null 2>&1 || true
TEMP_UID="$(/usr/bin/id -u "$TEMP_USER")"
printf '%s\n' "$TEMP_USER" >"$ACTIVE_STATE/temp.user"
printf '%s\n' "$DISPLAY_NAME" >"$ACTIVE_STATE/display.name"
printf '%s\n' "$DISPLAY_NAME" >"$LOG_DIR/last_display_name.txt"
log_line "LAUNCH" "THROWAY_USER uid=$TEMP_UID short=$TEMP_USER display=$DISPLAY_NAME"

# Aqua session of the logged-in desktop, process uid of the throwaway user.
# Do not launch Zoom with osascript. Do not fall back to the console user.
launch_as_temp() {
  log_line "LAUNCH" "launchctl asuser $CONSOLE_UID sudo -u $TEMP_USER $*"
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$TEMP_USER" "$@" >/dev/null 2>&1 &
}

launch_as_temp /usr/bin/env \
  HOME="$TEMP_HOME" \
  CFFIXED_USER_HOME="$TEMP_HOME" \
  TMPDIR="$TEMP_HOME/tmp/" \
  CFPREFERENCES_AVOID_DAEMON=1 \
  USER="$TEMP_USER" \
  LOGNAME="$TEMP_USER" \
  "$ZOOM_BIN"

if ! wait_for_uid_zoom "$TEMP_UID" 12; then
  log_line "LAUNCH" "retry sudo -u without extra env"
  launch_as_temp -H "$ZOOM_BIN"
fi

if ! wait_for_uid_zoom "$TEMP_UID" 8; then
  log_line "LAUNCH" "retry sudo -u then asuser"
  /usr/bin/sudo -u "$TEMP_USER" /bin/launchctl asuser "$CONSOLE_UID" "$ZOOM_BIN" >/dev/null 2>&1 &
  wait_for_uid_zoom "$TEMP_UID" 10 || true
fi

kill_login_zoom

if ! zoom_for_uid "$TEMP_UID"; then
  log_line "LAUNCH" "FAILED Zoom did not start as the throwaway user"
  delete_temp_user "$TEMP_USER"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "launch-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  show_dialog "1132.WTF" "Zoom did not start as the throwaway user, so it was not opened as your Mac login. Regular Zoom was restored. Run STEP 1 again." "stop"
  exit 72
fi

log_line "LAUNCH" "OK Zoom is running as throwaway uid=$TEMP_UID name-ready=YES"
/usr/bin/nohup /bin/bash "$SELF" --watch "$ACTIVE_STATE" "$TEMP_USER" "$TEMP_UID" >>"$LOG_FILE" 2>&1 &
printf '%s\n' "$!" >"$ACTIVE_STATE/monitor.pid"
printf '%s' "$DISPLAY_NAME" | /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/pbcopy >/dev/null 2>&1 || true
notify_user "1132.WTF" "Fresh Zoom is opening as $DISPLAY_NAME"
show_dialog "1132.WTF" "Fresh Zoom is open as:

$DISPLAY_NAME

That must not be your Mac login name. Click Join. When you quit Zoom, this throwaway user is deleted and your regular Zoom is restored." "note"
exit 0
