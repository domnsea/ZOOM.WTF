#!/bin/bash
#
# Throwaway-user helper. Runs as root.
#
# --prepare DIR  create the hidden wtf1132tmp user and start a watcher, then
#                return. The engine (not this script) opens Zoom on screen.
# --watch        wait until Zoom quits, then delete wtf1132tmp.
#
# This script must not launch Zoom itself. A root/osascript process has no
# desktop, so Zoom started from here never appears — and a later killall
# was killing Zoom if the app did manage to open it.

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

if [ "${1:-}" = "--prepare" ]; then
  DIR="${2:-}"
  [ -d "$DIR" ] || die "session dir missing: $DIR"
  LOG="$(cat "$DIR/session.log" 2>/dev/null || printf '%s' "$DIR/session.log")"
  mkdir -p "$(dirname "$LOG")"

  if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
    printf '%s\n' "[INFO] leftover $TEMP_USER exists, deleting it first" >>"$LOG"
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

  /usr/bin/dscl . -create "/Users/$TEMP_USER" IsHidden 1 >/dev/null 2>&1 || true
  /usr/sbin/createhomedir -c -u "$TEMP_USER" >/dev/null 2>&1 || true
  printf '%s\n' "[OK] created hidden user $TEMP_USER" >>"$LOG"

  nohup /bin/bash "$0" --watch >>"$LOG" 2>&1 &
  printf '%s\n' "watcher pid $!"
  exit 0
fi

[ "${1:-}" = "--watch" ] || die "Usage: $0 --prepare <dir>"

printf '%s\n' "[START] waiting for Zoom to appear, then for you to quit it"

# Wait until Zoom is actually on screen. Do not treat "not running yet" as quit.
appeared=0
waited=0
while [ "$waited" -lt 60 ]; do
  if /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1 || \
     /usr/bin/pgrep -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1; then
    appeared=1
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

if [ "$appeared" -ne 1 ]; then
  printf '%s\n' "[WARN] Zoom never appeared. Deleting $TEMP_USER."
else
  printf '%s\n' "[OK] Zoom is running. Waiting until you quit it."
  while /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1 || \
        /usr/bin/pgrep -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1; do
    sleep 2
  done
  printf '%s\n' "[ACTION] Zoom exited. Deleting $TEMP_USER"
fi

assert_safe_user "$TEMP_USER"
if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  /usr/sbin/sysadminctl -deleteUser "$TEMP_USER" >/dev/null 2>&1 || true
fi
/bin/rm -rf "/Users/$TEMP_USER" >/dev/null 2>&1 || true

if /usr/bin/dscl . -read "/Users/$TEMP_USER" >/dev/null 2>&1; then
  printf '%s\n' "[WARN] $TEMP_USER is still on the system"
  exit 1
fi

printf '%s\n' "[DONE] $TEMP_USER deleted"
exit 0
