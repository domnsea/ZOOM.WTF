#!/bin/bash
#
# Same Mac login. Blank Zoom profile. Open Zoom on this desktop.
# Pre-saved Zoom settings are moved aside for this session and put
# back when Zoom quits. No throwaway OS user. No keychain circus.
#
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SELF="$SCRIPT_DIR/$(basename "$0")"

if [ "$(id -u)" -ne 0 ]; then
  exec /usr/bin/sudo -p "Password: " /bin/bash "$SELF" "$@"
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
export CONSOLE_UID CONSOLE_USER CONSOLE_HOME

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

log_line "LAUNCH" "START blank-profile console_uid=$CONSOLE_UID user=$CONSOLE_USER"

stop_leftover_watchers() {
  local pid
  pid="$(read_state_line "$ACTIVE_STATE/monitor.pid")"
  case "$pid" in
    '' | *[!0-9]*) ;;
    *) /bin/kill -9 "$pid" >/dev/null 2>&1 || true ;;
  esac
  /usr/bin/pkill -9 -f "launch_fresh_zoom.sh --watch" >/dev/null 2>&1 || true
  /usr/bin/pkill -9 -f "/monitor_zoom.sh " >/dev/null 2>&1 || true
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

ZOOM6_VERSION="6.3.11.50104"
ZOOM6_CACHE="/Library/Application Support/1132.WTF/zoom-6.3.11"
ZOOM6_APP="$ZOOM6_CACHE/zoom.us.app"

zoom6_ready() {
  [ -x "$ZOOM6_APP/Contents/MacOS/zoom.us" ] || return 1
  local ver
  ver="$(/usr/bin/defaults read "$ZOOM6_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
  case "$ver" in
    6.3.11*) return 0 ;;
  esac
  return 1
}

extract_zoom6_pkg() {
  local pkg="$1" dest="$2"
  /bin/rm -rf "$dest"
  /bin/mkdir -p "$dest"
  if /usr/sbin/pkgutil --expand-full "$pkg" "$dest/expanded" >/dev/null 2>&1; then
    :
  else
    (
      cd "$dest" || exit 1
      /usr/bin/xar -xf "$pkg" >/dev/null 2>&1 || exit 1
      if [ -f Payload ]; then
        /usr/bin/gunzip -dc Payload 2>/dev/null | /usr/bin/cpio -idm >/dev/null 2>&1 || true
      fi
    ) || return 1
  fi
  local found
  found="$(/usr/bin/find "$dest" -name 'zoom.us.app' -type d 2>/dev/null | /usr/bin/head -n 1)"
  [ -n "$found" ] && [ -d "$found" ] || return 1
  /bin/mkdir -p "$ZOOM6_CACHE"
  /bin/rm -rf "$ZOOM6_APP"
  /bin/cp -R "$found" "$ZOOM6_APP"
  /usr/bin/find "$ZOOM6_APP" \( -iname '*AutoUpdater*' -o -iname '*ZoomOpener*' \) -exec /bin/rm -rf {} + 2>/dev/null || true
  /usr/sbin/chown -R root:wheel "$ZOOM6_CACHE" >/dev/null 2>&1 || true
  return 0
}

# Open whatever Zoom is already on this Mac. Only download 6.3.11 if
# there is no Zoom.app at all. Waiting on a 150 MB fetch is why STEP 1
# felt stuck.
resolve_zoom_app() {
  local found
  found="$(find_zoom_app || true)"
  if [ -n "$found" ] && [ -x "$found/Contents/MacOS/zoom.us" ]; then
    ZOOM_APP="$found"
    log_line "LAUNCH" "using installed Zoom $ZOOM_APP"
    return 0
  fi
  if [ -n "$found" ] && [ -x "$found/Contents/MacOS/ZoomOpener" ]; then
    ZOOM_APP="$found"
    log_line "LAUNCH" "using installed Zoom $ZOOM_APP"
    return 0
  fi
  if zoom6_ready; then
    ZOOM_APP="$ZOOM6_APP"
    log_line "ZOOM6" "using cached Zoom 6.3.11"
    return 0
  fi
  notify_user "1132.WTF" "No Zoom.app on this Mac. Downloading Zoom 6.3.11 from zoom.us"
  local arch url tmp
  arch="$(/usr/bin/uname -m)"
  url="https://zoom.us/client/${ZOOM6_VERSION}/zoomusInstallerFull.pkg"
  if [ "$arch" = "arm64" ]; then
    url="${url}?archType=arm64"
  fi
  tmp="$(/usr/bin/mktemp -d /tmp/1132zoom6.XXXXXX)"
  if ! /usr/bin/curl -fL --retry 3 --connect-timeout 20 --max-time 600 -o "$tmp/zoom.pkg" "$url"; then
    /bin/rm -rf "$tmp"
    show_dialog "1132.WTF" "No Zoom.app in Applications, and Zoom 6.3.11 could not be downloaded. Install Zoom, then run STEP 1 again." "stop"
    exit 69
  fi
  if ! extract_zoom6_pkg "$tmp/zoom.pkg" "$tmp/extract" || ! zoom6_ready; then
    /bin/rm -rf "$tmp"
    show_dialog "1132.WTF" "Could not unpack Zoom. Install Zoom in Applications, then run STEP 1 again." "stop"
    exit 69
  fi
  /bin/rm -rf "$tmp"
  ZOOM_APP="$ZOOM6_APP"
}

zoom_for_uid() {
  local uid="$1"
  /usr/bin/pgrep -u "$uid" -x "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -u "$uid" -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -u "$uid" -f "Zoom Workplace.app/Contents/MacOS" >/dev/null 2>&1 && return 0
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

unload_zoom_helpers() {
  local agent
  bootout_zoom_system_jobs
  for agent in \
    "$CONSOLE_HOME/Library/LaunchAgents/us.zoom.updater.plist" \
    "$CONSOLE_HOME/Library/LaunchAgents/us.zoom.ZoomAutoUpdater.plist" \
    /Library/LaunchAgents/us.zoom.updater.plist \
    /Library/LaunchAgents/us.zoom.ZoomAutoUpdater.plist
  do
    [ -f "$agent" ] || continue
    /bin/launchctl bootout "gui/$CONSOLE_UID" "$agent" >/dev/null 2>&1 ||
      /bin/launchctl unload "$agent" >/dev/null 2>&1 || true
  done
}

# This desktop session. Isolated HOME so Zoom cannot see the saved profile.
as_console() {
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" -H /usr/bin/env \
    HOME="$RUNTIME_HOME" \
    CFFIXED_USER_HOME="$RUNTIME_HOME" \
    CFPREFERENCES_AVOID_DAEMON=1 \
    TMPDIR="$RUNTIME_HOME/tmp/" \
    USER="$CONSOLE_USER" \
    LOGNAME="$CONSOLE_USER" \
    "$@"
}

wipe_user_zoom_keychain() {
  local item n
  for item in \
    "Zoom Safe Meeting Storage" \
    "zoom.us" \
    "Zoom" \
    "us.zoom.xos" \
    "Zoom SSO" \
    "ZoomChat" \
    "ZoomAutoUpdater" \
    "us.zoom.updater" \
    "us.zoom.ZoomDaemon"
  do
    n=0
    while [ "$n" -lt 40 ]; do
      /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" -H \
        /usr/bin/security delete-generic-password -l "$item" >/dev/null 2>&1 || break
      n=$((n + 1))
    done
    n=0
    while [ "$n" -lt 40 ]; do
      /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" -H \
        /usr/bin/security delete-generic-password -s "$item" >/dev/null 2>&1 || break
      n=$((n + 1))
    done
  done
  log_line "LAUNCH" "login keychain Zoom items removed for this session"
}

fail_blank_launch() {
  local reason="$1"
  log_line "LAUNCH" "FAILED $reason"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "launch-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  show_dialog "1132.WTF" "Zoom did not stay open. Regular Zoom settings were put back. Run STEP 1 again." "stop"
  exit 72
}

if [ "${1:-}" = "--watch" ]; then
  STATE_DIR="${2:-$ACTIVE_STATE}"
  log_line "WATCH" "waiting for blank-profile Zoom to quit"
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
      /usr/bin/killall -9 ZoomDaemon us.zoom.ZoomDaemon ZoomOpener ZoomAutoUpdater >/dev/null 2>&1 || true
      /bin/sleep 2
    done
  fi
  export HOME="$CONSOLE_HOME"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$STATE_DIR" "zoom-closed" || true
  log_line "WATCH" "DONE blank profile deleted and regular Zoom restored"
  exit 0
fi

/usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost ZoomDaemon >/dev/null 2>&1 || true
/usr/bin/pkill -9 -f "/zoom.us.app/" >/dev/null 2>&1 || true
unload_zoom_helpers
/bin/sleep 1

# Put Applications Zoom back if an older build hid it, then open it.
stop_leftover_watchers
if [[ -d "$ACTIVE_STATE" ]]; then
  log_line "LAUNCH" "RECOVERY leftover session"
  leftover="$(read_state_line "$ACTIVE_STATE/temp.user")"
  [ -n "$leftover" ] && delete_temp_user "$leftover"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "startup-recovery" || true
  printf '%s\n' "Previous session cleaned up. Opening a new Zoom..."
fi

resolve_zoom_app
ZOOM_BIN=""
if [ -x "$ZOOM_APP/Contents/MacOS/zoom.us" ]; then
  ZOOM_BIN="$ZOOM_APP/Contents/MacOS/zoom.us"
elif [ -x "$ZOOM_APP/Contents/MacOS/ZoomOpener" ]; then
  ZOOM_BIN="$ZOOM_APP/Contents/MacOS/ZoomOpener"
fi
if [ -z "$ZOOM_BIN" ]; then
  show_dialog "1132.WTF" "Zoom.app is missing its executable. Install Zoom, then run STEP 1 again." "stop"
  exit 69
fi
log_line "LAUNCH" "ZOOM_BIN=$ZOOM_BIN"

/bin/rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true

if ! /bin/mkdir "$LOCK_DIR" 2>/dev/null; then
  show_dialog "1132.WTF" "Another 1132.WTF launch is still active. Quit Zoom, wait a few seconds, then run STEP 1 again." "stop"
  exit 75
fi

RUNTIME_HOME="$ACTIVE_STATE/runtime-home"
/bin/mkdir -p "$ACTIVE_STATE/backup" "$RUNTIME_HOME" "$ACTIVE_STATE/runtime-scripts"
/bin/chmod 700 "$ACTIVE_STATE" "$ACTIVE_STATE/backup" "$RUNTIME_HOME"
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

# Machine Zoom tokens only. Do not hide Applications Zoom — that is what
# we are about to open.
stash_system_zoom "$ACTIVE_STATE"
wipe_user_zoom_keychain
sweep_stray_zoom_identity "$ACTIVE_STATE/stray-zoom"

/bin/mkdir -p \
  "$RUNTIME_HOME/tmp" \
  "$RUNTIME_HOME/Library/Application Support" \
  "$RUNTIME_HOME/Library/Preferences" \
  "$RUNTIME_HOME/Library/Caches" \
  "$RUNTIME_HOME/Library/Logs" \
  "$RUNTIME_HOME/Library/Keychains"
/usr/sbin/chown -R "$CONSOLE_USER:staff" "$RUNTIME_HOME" >/dev/null 2>&1 || true

# Empty profile. No ZoomDisplayName, no saved rooms, no signed-in account.
log_line "LAUNCH" "launchctl asuser $CONSOLE_UID sudo -u $CONSOLE_USER blank HOME=$RUNTIME_HOME"
as_console "$ZOOM_BIN" >/dev/null 2>&1 &

if ! wait_for_uid_zoom "$CONSOLE_UID" 12; then
  log_line "LAUNCH" "retry blank-profile Zoom"
  as_console "$ZOOM_BIN" >/dev/null 2>&1 &
  wait_for_uid_zoom "$CONSOLE_UID" 10 || true
fi

if ! zoom_for_uid "$CONSOLE_UID"; then
  fail_blank_launch "Zoom did not start on this desktop"
fi

stable=0
waited=0
while [ "$waited" -lt 8 ]; do
  if zoom_for_uid "$CONSOLE_UID"; then
    stable=$((stable + 1))
  else
    fail_blank_launch "Zoom exited during startup"
  fi
  /bin/sleep 1
  waited=$((waited + 1))
done

log_line "LAUNCH" "OK Zoom is running as $CONSOLE_USER uid=$CONSOLE_UID stable=$stable blank-profile=YES"
/usr/bin/nohup /bin/bash "$SELF" --watch "$ACTIVE_STATE" >>"$LOG_FILE" 2>&1 &
printf '%s\n' "$!" >"$ACTIVE_STATE/monitor.pid"
notify_user "1132.WTF" "Fresh Zoom is opening. Join in THIS window."
show_dialog "1132.WTF" "Zoom is open on a blank profile.

No saved rooms, no signed-in account, no old settings.

Join in THIS window.

When you quit Zoom, your regular Zoom is put back." "note"
exit 0
