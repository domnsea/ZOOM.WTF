#!/bin/bash
#
# Same-screen throwaway Zoom session.
#
# Runs as root (started by the engine's admin prompt). Creates a hidden
# wtf1132tmp user, opens Zoom as that user on the current desktop, waits
# until that Zoom exits, then deletes the user. The password is never shown
# and is never written to a log.

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

# --start-from DIR: read zoom.path / join.url / display.name / session.log
# then detach a watcher and return so the app is not blocked.
if [ "${1:-}" = "--start-from" ]; then
  DIR="${2:-}"
  [ -d "$DIR" ] || die "session dir missing: $DIR"
  ZOOM_APP="$(cat "$DIR/zoom.path" 2>/dev/null || true)"
  JOIN_URL="$(cat "$DIR/join.url" 2>/dev/null || true)"
  DISPLAY_NAME="$(cat "$DIR/display.name" 2>/dev/null || printf 'Guest')"
  LOG="$(cat "$DIR/session.log" 2>/dev/null || printf '%s' "$DIR/session.log")"
  mkdir -p "$(dirname "$LOG")"
  nohup /bin/bash "$0" --watch "$ZOOM_APP" "$JOIN_URL" "$DISPLAY_NAME" >>"$LOG" 2>&1 &
  printf '%s\n' "session watcher pid $!"
  exit 0
fi

[ "${1:-}" = "--watch" ] || die "Usage: $0 --start-from <dir>"
shift

ZOOM_APP="${1:-}"
JOIN_URL="${2:-}"
DISPLAY_NAME="${3:-Guest}"

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

printf '%s\n' "[START] same-screen session for $TEMP_USER (console=$CONSOLE_USER)"

# ------------------------------------------------------------------ create

if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  printf '%s\n' "[INFO] leftover $TEMP_USER exists, deleting it first"
  /usr/sbin/sysadminctl -deleteUser "$TEMP_USER" >/dev/null 2>&1 || true
  /bin/rm -rf "/Users/$TEMP_USER" >/dev/null 2>&1 || true
fi

PASSWORD="$(/usr/bin/openssl rand -base64 24 | /usr/bin/tr -d '/+=' | /usr/bin/head -c 20)"
[ -n "$PASSWORD" ] || die "Could not generate a password."

if ! /usr/sbin/sysadminctl -addUser "$TEMP_USER" \
  -fullName "$APP_NAME Guest" \
  -password "$PASSWORD" >/dev/null 2>&1; then
  die "sysadminctl could not create $TEMP_USER"
fi

# Hidden: must not appear in Users & Groups or the Fast User Switching list.
/usr/bin/dscl . -create "/Users/$TEMP_USER" IsHidden 1 >/dev/null 2>&1 || true
/usr/sbin/createhomedir -c -u "$TEMP_USER" >/dev/null 2>&1 || true

HOME_DIR="$(/usr/bin/dscl . -read "/Users/$TEMP_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$HOME_DIR" ] || HOME_DIR="/Users/$TEMP_USER"
DATA_DIR="$HOME_DIR/zoom-data"
/bin/mkdir -p "$DATA_DIR"
/usr/sbin/chown -R "$TEMP_USER:staff" "$HOME_DIR" >/dev/null 2>&1 || true

TEMP_UID="$(/usr/bin/id -u "$TEMP_USER")"
printf '%s\n' "[OK] created hidden user $TEMP_USER uid=$TEMP_UID"

# ------------------------------------------------------------------- launch

# Force-close any Zoom still on this Mac so we do not attach to dustin's session.
/usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
/usr/bin/pkill -9 -f "/zoom.us.app/" >/dev/null 2>&1 || true
sleep 1

ARGS=(--data="$DATA_DIR")
if [ -n "$JOIN_URL" ]; then
  ARGS+=(--url="$JOIN_URL")
fi

# Run the Zoom binary as the throwaway user, but inside the logged-in user's
# Aqua session so the window appears on THIS desktop (no profile switch).
printf '%s\n' "[ACTION] launching Zoom as $TEMP_USER on $CONSOLE_USER's screen"
/bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$TEMP_USER" \
  "$ZOOM_BIN" "${ARGS[@]}" >/dev/null 2>&1 &
sleep 4

zoom_for_temp() {
  /usr/bin/pgrep -u "$TEMP_UID" -f "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "$DATA_DIR" >/dev/null 2>&1 && return 0
  return 1
}

if ! zoom_for_temp; then
  printf '%s\n' "[WARN] uid launch did not appear, opening Zoom with the temp profile on this screen"
  /bin/launchctl asuser "$CONSOLE_UID" \
    "$ZOOM_BIN" "${ARGS[@]}" >/dev/null 2>&1 &
  sleep 3
fi

if zoom_for_temp || /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1; then
  printf '%s\n' "[OK] Zoom is running. Waiting until you quit it."
else
  printf '%s\n' "[WARN] Zoom did not start. Cleaning up the temp user."
fi

# --------------------------------------------------------------------- wait

# Until Zoom (and helpers using this data dir) are gone.
waited=0
# Give it a moment to actually come up before we treat "not running" as quit.
sleep 2
while zoom_for_temp || /usr/bin/pgrep -f "$DATA_DIR" >/dev/null 2>&1; do
  sleep 2
  waited=$((waited + 2))
  # Safety valve: 8 hours. Do not leave a hidden user forever if Zoom hangs.
  if [ "$waited" -gt 28800 ]; then
    printf '%s\n' "[WARN] timed out waiting for Zoom to quit"
    break
  fi
done

printf '%s\n' "[ACTION] Zoom exited. Deleting $TEMP_USER"

/usr/bin/killall -9 zoom.us ZoomOpener CptHost aomhost >/dev/null 2>&1 || true

assert_safe_user "$TEMP_USER"
if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  /usr/sbin/sysadminctl -deleteUser "$TEMP_USER" >/dev/null 2>&1 || true
fi
/bin/rm -rf "/Users/$TEMP_USER" "$HOME_DIR" >/dev/null 2>&1 || true

if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  printf '%s\n' "[WARN] $TEMP_USER is still on the system"
  exit 1
fi

printf '%s\n' "[DONE] $TEMP_USER deleted"
exit 0
