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

# Current Zoom (7 / latest Workplace) is still 1132. Pin this session to
# official Zoom 6.3.11 from zoom.us — not the copy in Applications.
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

ensure_zoom6() {
  if zoom6_ready; then
    log_line "ZOOM6" "using cached Zoom 6.3.11 at $ZOOM6_APP"
    return 0
  fi
  notify_user "1132.WTF" "Downloading Zoom 6.3.11 from zoom.us"
  show_dialog "1132.WTF" "This run uses Zoom 6.3.11, not the current Zoom in Applications.

The first run downloads it from zoom.us (~150 MB). Wait. Do not open the Zoom in Applications." "note"
  local arch url tmp
  arch="$(/usr/bin/uname -m)"
  url="https://zoom.us/client/${ZOOM6_VERSION}/zoomusInstallerFull.pkg"
  if [ "$arch" = "arm64" ]; then
    url="${url}?archType=arm64"
  fi
  tmp="$(/usr/bin/mktemp -d /tmp/1132zoom6.XXXXXX)"
  log_line "ZOOM6" "download $url"
  if ! /usr/bin/curl -fL --retry 3 --connect-timeout 20 --max-time 600 -o "$tmp/zoom.pkg" "$url"; then
    /bin/rm -rf "$tmp"
    show_dialog "1132.WTF" "Could not download Zoom 6.3.11 from zoom.us. Check the network and run STEP 1 again. The current Zoom in Applications was not used." "stop"
    exit 69
  fi
  if ! extract_zoom6_pkg "$tmp/zoom.pkg" "$tmp/extract"; then
    /bin/rm -rf "$tmp"
    show_dialog "1132.WTF" "Downloaded Zoom 6.3.11 but could not unpack it. Run STEP 1 again." "stop"
    exit 69
  fi
  /bin/rm -rf "$tmp"
  if ! zoom6_ready; then
    show_dialog "1132.WTF" "Zoom 6.3.11 did not install. The current Zoom in Applications was not used." "stop"
    exit 69
  fi
  log_line "ZOOM6" "installed Zoom 6.3.11"
}

ensure_zoom6
ZOOM_APP="$ZOOM6_APP"
ZOOM_BIN="$ZOOM_APP/Contents/MacOS/zoom.us"
if [[ ! -x "$ZOOM_BIN" ]]; then
  show_dialog "1132.WTF" "Zoom 6.3.11 is missing its executable. Run STEP 1 again." "stop"
  exit 69
fi
log_line "LAUNCH" "ZOOM_BIN=$ZOOM_BIN version=6.3.11"

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
  /usr/bin/killall -9 ZoomOpener ZoomAutoUpdater >/dev/null 2>&1 || true
}

# After a failed throwaway launch, restore the regular profile but do not
# let LaunchServices reopen Zoom as the Mac login (that is the "same
# dustin profile" bug after the keychain dialogs).
hold_zoom_closed() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    /usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
    kill_login_zoom
    /bin/sleep 1
  done
}

unload_zoom_helpers() {
  local agent
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
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/osascript -e \
    'tell application "System Events" to delete (every login item whose name contains "zoom")' \
    >/dev/null 2>&1 || true
}

# Same Aqua session Zoom will use. Always HOME=throwaway, never the login home.
as_temp() {
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$TEMP_USER" -H /usr/bin/env \
    HOME="$TEMP_HOME" \
    CFFIXED_USER_HOME="$TEMP_HOME" \
    TMPDIR="$TEMP_HOME/tmp/" \
    USER="$TEMP_USER" \
    LOGNAME="$TEMP_USER" \
    "$@"
}

# Hidden users created with sysadminctl never get a login keychain until a
# GUI login. Zoom then shows "A keychain cannot be found to store Zoom",
# dies, and the regular profile reopens as the Mac login.
prepare_temp_keychain() {
  local kcdir="$TEMP_HOME/Library/Keychains"
  local kc="$kcdir/login.keychain-db"
  local kc_old="$kcdir/login.keychain"
  local use=""
  /bin/mkdir -p "$kcdir" "$TEMP_HOME/tmp"
  /usr/sbin/chown -R "$TEMP_USER:staff" "$TEMP_HOME/Library" "$TEMP_HOME/tmp" >/dev/null 2>&1 || true
  /bin/rm -f "$kc" "$kc_old" "$kcdir/metadata.keychain-db" 2>/dev/null || true

  if as_temp /usr/bin/security create-keychain -p "$PASSWORD" "$kc" >/dev/null 2>&1; then
    use="$kc"
  elif as_temp /usr/bin/security create-keychain -p "$PASSWORD" "$kc_old" >/dev/null 2>&1; then
    use="$kc_old"
  elif as_temp /usr/bin/security create-keychain -p "$PASSWORD" login.keychain >/dev/null 2>&1; then
    if [ -f "$kc" ]; then
      use="$kc"
    else
      use="$kc_old"
    fi
  fi
  if [ -z "$use" ] || [ ! -f "$use" ]; then
    log_line "LAUNCH" "WARNING could not create throwaway login keychain"
    return 1
  fi

  as_temp /usr/bin/security default-keychain -d user -s "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security unlock-keychain -p "$PASSWORD" "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security set-keychain-settings "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security list-keychains -d user -s "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s -k "$PASSWORD" "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security add-generic-password -a "$TEMP_USER" -s "us.zoom.xos" -w "none" -T "$ZOOM_BIN" -T "/usr/bin/security" "$use" >/dev/null 2>&1 || true
  as_temp /usr/bin/security add-generic-password -a "Zoom" -s "Zoom" -w "none" -T "$ZOOM_BIN" "$use" >/dev/null 2>&1 || true
  /usr/sbin/chown -R "$TEMP_USER:staff" "$kcdir" >/dev/null 2>&1 || true
  log_line "LAUNCH" "KEYCHAIN ready path=$use"
  return 0
}

seed_zoom_prefs() {
  as_temp /usr/bin/defaults write us.zoom.xos ZoomDisplayName "$DISPLAY_NAME" >/dev/null 2>&1 || true
  as_temp /usr/bin/defaults write us.zoom.xos UserName "$DISPLAY_NAME" >/dev/null 2>&1 || true
  as_temp /usr/bin/defaults write us.zoom.xos nologin -bool true >/dev/null 2>&1 || true
  as_temp /usr/bin/defaults write us.zoom.xos AutoLogin -bool false >/dev/null 2>&1 || true
  as_temp /usr/bin/defaults write us.zoom.xos zDisableAutoUpdate -bool true >/dev/null 2>&1 || true
  as_temp /usr/bin/defaults write us.zoom.xos AutoUpdate -bool false >/dev/null 2>&1 || true
  /usr/sbin/chown -R "$TEMP_USER:staff" "$TEMP_HOME/Library/Preferences" >/dev/null 2>&1 || true
}

fail_throwaway_launch() {
  local reason="$1"
  log_line "LAUNCH" "FAILED $reason"
  delete_temp_user "$TEMP_USER"
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "launch-failed" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  hold_zoom_closed
  show_dialog "1132.WTF" "Zoom did not stay open as the throwaway user (that is the keychain error). It was not left open as your Mac login. Regular Zoom was restored and kept closed. Run STEP 1 again." "stop"
  exit 72
}

if [ "${1:-}" = "--watch" ]; then
  STATE_DIR="${2:-$ACTIVE_STATE}"
  TEMP_USER="${3:-}"
  TEMP_UID="${4:-}"
  log_line "WATCH" "waiting for throwaway Zoom to quit"
  appeared=0
  waited=0
  while [ "$waited" -lt 180 ]; do
    kill_login_zoom
    if [ -n "$TEMP_UID" ] && zoom_for_uid "$TEMP_UID"; then
      appeared=1
      break
    fi
    /bin/sleep 1
    waited=$((waited + 1))
  done
  if [ "$appeared" -eq 1 ]; then
    while zoom_for_uid "$TEMP_UID"; do
      kill_login_zoom
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
unload_zoom_helpers
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

stash_system_zoom "$ACTIVE_STATE"
if ! require_new_public_ip "$ACTIVE_STATE"; then
  /bin/bash "$SCRIPT_DIR/restore_profile.sh" "$ACTIVE_STATE" "ip-unchanged" || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  exit 73
fi

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
  "$TEMP_HOME/Library/Logs" \
  "$TEMP_HOME/Library/Keychains"
/usr/sbin/chown -R "$TEMP_USER:staff" "$TEMP_HOME" >/dev/null 2>&1 || true
TEMP_UID="$(/usr/bin/id -u "$TEMP_USER")"
printf '%s\n' "$TEMP_USER" >"$ACTIVE_STATE/temp.user"
printf '%s\n' "$DISPLAY_NAME" >"$ACTIVE_STATE/display.name"
printf '%s\n' "$DISPLAY_NAME" >"$LOG_DIR/last_display_name.txt"
log_line "LAUNCH" "THROWAY_USER uid=$TEMP_UID short=$TEMP_USER display=$DISPLAY_NAME"

if ! prepare_temp_keychain; then
  fail_throwaway_launch "throwaway keychain was not created"
fi
seed_zoom_prefs
save_and_rotate_network "$ACTIVE_STATE"

# Aqua session of the logged-in desktop, process uid of the throwaway user.
# Always pass the throwaway HOME. Never launch with the login account home.
launch_as_temp() {
  log_line "LAUNCH" "launchctl asuser $CONSOLE_UID sudo -u $TEMP_USER $*"
  as_temp "$@" >/dev/null 2>&1 &
}

launch_as_temp "$ZOOM_BIN"

if ! wait_for_uid_zoom "$TEMP_UID" 12; then
  log_line "LAUNCH" "retry sudo -u with throwaway env"
  launch_as_temp /usr/bin/env \
    HOME="$TEMP_HOME" \
    CFFIXED_USER_HOME="$TEMP_HOME" \
    CFPREFERENCES_AVOID_DAEMON=1 \
    USER="$TEMP_USER" \
    LOGNAME="$TEMP_USER" \
    "$ZOOM_BIN"
  wait_for_uid_zoom "$TEMP_UID" 10 || true
fi

kill_login_zoom

if ! zoom_for_uid "$TEMP_UID"; then
  fail_throwaway_launch "Zoom did not start as the throwaway user"
fi

# Keychain dialogs used to kill throwaway Zoom in a few seconds, then the
# restored login profile reopened. Wait until this instance stays up.
stable=0
waited=0
while [ "$waited" -lt 12 ]; do
  kill_login_zoom
  if zoom_for_uid "$TEMP_UID"; then
    stable=$((stable + 1))
  else
    fail_throwaway_launch "throwaway Zoom exited during startup (keychain)"
  fi
  /bin/sleep 1
  waited=$((waited + 1))
done

log_line "LAUNCH" "OK Zoom is running as throwaway uid=$TEMP_UID stable=$stable name-ready=YES"
/usr/bin/nohup /bin/bash "$SELF" --watch "$ACTIVE_STATE" "$TEMP_USER" "$TEMP_UID" >>"$LOG_FILE" 2>&1 &
printf '%s\n' "$!" >"$ACTIVE_STATE/monitor.pid"
printf '%s' "$DISPLAY_NAME" | /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/pbcopy >/dev/null 2>&1 || true
notify_user "1132.WTF" "Fresh Zoom is opening as $DISPLAY_NAME"
show_dialog "1132.WTF" "Zoom 6.3.11 is open as:

$DISPLAY_NAME

The Zoom in Applications is hidden for this session. Public IP changed.

If Join still says 1132 on this new IP, this Mac's hardware id is blocked. No app can rewrite that.

When you quit Zoom, Applications Zoom, MAC, and name are put back." "note"
exit 0
