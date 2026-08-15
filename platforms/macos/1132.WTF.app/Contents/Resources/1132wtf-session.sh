#!/bin/bash
#
# Throwaway-user helper. Runs as root.
#
# --start-from DIR  detach a watcher and return.
# --prepare DIR     same as --start-from (kept for older callers / tests).
# --watch DIR       create hidden wtf1132tmp, launch Zoom as THAT user on
#                   this desktop with launchctl asuser + sudo -u (not
#                   osascript), wait until Zoom quits, delete the user.
#
# Zoom must run as wtf1132tmp. Running it as the logged-in user (even with
# HOME pointed at the temp folder) still sends that login name — that is
# why the name stayed the Mac account name.

set -u

APP_NAME="1132.WTF"
TEMP_USER="wtf1132tmp"
SLOT_PREFIX="wtf1132"

die() { printf '%s\n' "FATAL: $*" >&2; exit 1; }

assert_safe_user() {
  case "$1" in
    "$SLOT_PREFIX"*) : ;;
    *) die "Refusing to act on '$1': not a $APP_NAME rotation account." ;;
  esac
}

assert_safe_user "$TEMP_USER"

if [ "$(id -u)" -ne 0 ]; then
  die "This helper must run as root."
fi

delete_temp_user() {
  assert_safe_user "$TEMP_USER"
  if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
    /usr/sbin/sysadminctl -deleteUser "$TEMP_USER" >/dev/null 2>&1 || true
  fi
  /bin/rm -rf "/Users/$TEMP_USER" >/dev/null 2>&1 || true
}

if [ "${1:-}" = "--start-from" ] || [ "${1:-}" = "--prepare" ]; then
  DIR="${2:-}"
  [ -d "$DIR" ] || die "session dir missing: $DIR"
  LOG="$(cat "$DIR/session.log" 2>/dev/null || printf '%s' "$DIR/session.log")"
  mkdir -p "$(dirname "$LOG")"
  nohup /bin/bash "$0" --watch "$DIR" >>"$LOG" 2>&1 &
  printf '%s\n' "watcher pid $!"
  exit 0
fi

[ "${1:-}" = "--watch" ] || die "Usage: $0 --start-from <dir>"
DIR="${2:-}"
[ -d "$DIR" ] || die "session dir missing: $DIR"

ZOOM_APP="$(tr -d '\r' <"$DIR/zoom.path" 2>/dev/null || true)"
JOIN_URL="$(tr -d '\r\n' <"$DIR/join.url" 2>/dev/null || true)"
DISPLAY_NAME="$(tr -d '\r\n' <"$DIR/display.name" 2>/dev/null || printf 'Guest')"
[ -n "$DISPLAY_NAME" ] || DISPLAY_NAME="Guest"

[ -d "$ZOOM_APP" ] || die "Zoom app not found: $ZOOM_APP"

ZOOM_BIN=""
for candidate in \
  "$ZOOM_APP/Contents/MacOS/zoom.us" \
  "$ZOOM_APP/Contents/MacOS/Zoom" \
  "$ZOOM_APP/Contents/MacOS/zoom"
do
  if [ -x "$candidate" ]; then
    ZOOM_BIN="$candidate"
    break
  fi
done
[ -n "$ZOOM_BIN" ] || die "No Zoom binary inside $ZOOM_APP"

CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null || true)"
[ -n "$CONSOLE_UID" ] || die "Could not find the logged-in console user."

printf '%s\n' "[START] launching Zoom as $TEMP_USER on $CONSOLE_USER's desktop"
printf '%s\n' "[INFO] display name=$DISPLAY_NAME console=$CONSOLE_USER/$CONSOLE_UID"

delete_temp_user

PASSWORD="$(/usr/bin/openssl rand -base64 24 | /usr/bin/tr -d '/+=' | /usr/bin/head -c 20)"
[ -n "$PASSWORD" ] || die "Could not generate a password."

# Full name from the window so Zoom cannot pick the Mac login name.
if ! /usr/sbin/sysadminctl -addUser "$TEMP_USER" \
  -fullName "$DISPLAY_NAME" \
  -password "$PASSWORD" >/dev/null 2>&1; then
  die "sysadminctl could not create $TEMP_USER"
fi

/usr/bin/dscl . -create "/Users/$TEMP_USER" IsHidden 1 >/dev/null 2>&1 || true
/usr/bin/dscl . -create "/Users/$TEMP_USER" RealName "$DISPLAY_NAME" >/dev/null 2>&1 || true
/usr/bin/dscl . -create "/Users/$TEMP_USER" UserShell /bin/bash >/dev/null 2>&1 || true
/usr/sbin/createhomedir -c -u "$TEMP_USER" >/dev/null 2>&1 || true

HOME_DIR="$(/usr/bin/dscl . -read "/Users/$TEMP_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$HOME_DIR" ] || HOME_DIR="/Users/$TEMP_USER"
/bin/mkdir -p \
  "$HOME_DIR/Library/Application Support" \
  "$HOME_DIR/Library/Preferences" \
  "$HOME_DIR/Library/Caches" \
  "$HOME_DIR/Library/Logs"
/usr/sbin/chown -R "$TEMP_USER:staff" "$HOME_DIR" >/dev/null 2>&1 || true

TEMP_UID="$(/usr/bin/id -u "$TEMP_USER")"
printf '%s\n' "[OK] created hidden user $TEMP_USER uid=$TEMP_UID name=$DISPLAY_NAME home=$HOME_DIR"

zoom_for_temp() {
  /usr/bin/pgrep -u "$TEMP_UID" -x "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -u "$TEMP_UID" -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  return 1
}

log_zoom_procs() {
  printf '%s\n' "[INFO] zoom processes:"
  /bin/ps -axo user,uid,pid,command | /usr/bin/awk 'tolower($0) ~ /zoom/ { print }' || true
}

# Original working launch: Aqua session of the logged-in desktop, process uid
# of the throwaway user. Do not launch Zoom with osascript. Do not fall back
# to the console user — that is how the Mac login name came back.
launch_as_temp() {
  printf '%s\n' "[ACTION] launchctl asuser $CONSOLE_UID sudo -u $TEMP_USER $*"
  /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$TEMP_USER" "$@" &
}

if [ -n "$JOIN_URL" ]; then
  launch_as_temp "$ZOOM_BIN" --url="$JOIN_URL"
else
  launch_as_temp "$ZOOM_BIN"
fi
sleep 4
log_zoom_procs

if ! zoom_for_temp; then
  printf '%s\n' "[INFO] retry sudo -u without --url"
  launch_as_temp "$ZOOM_BIN"
  sleep 3
  log_zoom_procs
fi

if ! zoom_for_temp; then
  printf '%s\n' "[INFO] retry sudo -u then asuser"
  /usr/bin/sudo -u "$TEMP_USER" /bin/launchctl asuser "$CONSOLE_UID" "$ZOOM_BIN" &
  sleep 3
  log_zoom_procs
fi

appeared=0
waited=0
while [ "$waited" -lt 180 ]; do
  if zoom_for_temp; then
    appeared=1
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

if [ "$appeared" -ne 1 ]; then
  printf '%s\n' "[WARN] Zoom as $TEMP_USER never appeared. Deleting $TEMP_USER."
  log_zoom_procs
else
  printf '%s\n' "[OK] Zoom is running as $TEMP_USER. Waiting until you quit it."
  log_zoom_procs
  while zoom_for_temp; do
    sleep 2
  done
  printf '%s\n' "[ACTION] Zoom exited. Deleting $TEMP_USER"
fi

delete_temp_user

if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  printf '%s\n' "[WARN] $TEMP_USER is still on the system"
  exit 1
fi

printf '%s\n' "[DONE] $TEMP_USER deleted"
exit 0
