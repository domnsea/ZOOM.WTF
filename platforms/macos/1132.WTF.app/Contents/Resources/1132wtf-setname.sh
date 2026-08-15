#!/bin/bash
#
# Root helper. Zoom Join uses the Mac account full name (NSFullUserName),
# not USER= and not uname= (Zoom 5.7+ ignores uname=). For this session
# the console user's RealName is set to the random Zoom name, then put
# back when Zoom quits.
#
set -u

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "FATAL: This helper must run as root." >&2
  exit 1
fi

SAVE="/var/root/1132wtf-realname.restore"

console_user() {
  /usr/bin/stat -f %Su /dev/console 2>/dev/null || true
}

read_realname() {
  /usr/bin/dscl . -read "/Users/$1" RealName 2>/dev/null |
    /usr/bin/awk 'NR==1 { sub(/^RealName:[[:space:]]*/, ""); if ($0 != "") print; next } { sub(/^[[:space:]]+/, ""); print }' |
    /usr/bin/paste -s -d ' ' -
}

zoom_running() {
  /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  return 1
}

restore_realname() {
  [ -f "$SAVE" ] || return 0
  local user old current
  user="$(/usr/bin/head -n 1 "$SAVE" 2>/dev/null || true)"
  old="$(/usr/bin/tail -n +2 "$SAVE" 2>/dev/null | /usr/bin/paste -s -d ' ' -)"
  current="$(console_user)"
  case "$user" in
    "" | root | daemon | nobody | wtf1132tmp | wtf1132a | wtf1132b | wtf1132c)
      /bin/rm -f "$SAVE"
      return 1
      ;;
  esac
  if [ -n "$current" ] && [ "$user" != "$current" ]; then
    return 1
  fi
  /usr/bin/dscl . -create "/Users/$user" RealName "${old:-$user}" >/dev/null 2>&1 || true
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
  /bin/rm -f "$SAVE"
  return 0
}

if [ "${1:-}" = "--restore" ]; then
  restore_realname
  exit 0
fi

if [ "${1:-}" = "--start-from" ]; then
  DIR="${2:-}"
  [ -d "$DIR" ] || exit 1
  NEW="$(/usr/bin/tr -d '\r\n' <"$DIR/display.name" 2>/dev/null || true)"
  case "$NEW" in
    "" | *\"* | *\'* | *$'\n'* | *';'* | *'$'* | *'`'* )
      printf '%s\n' "FATAL: bad display name" >&2
      exit 1
      ;;
  esac
  CONSOLE="$(console_user)"
  case "$CONSOLE" in
    "" | root | daemon | nobody)
      printf '%s\n' "FATAL: no console user" >&2
      exit 1
      ;;
  esac
  restore_realname
  OLD="$(read_realname "$CONSOLE")"
  [ -n "$OLD" ] || OLD="$CONSOLE"
  printf '%s\n%s\n' "$CONSOLE" "$OLD" >"$SAVE"
  /bin/chmod 600 "$SAVE"
  if ! /usr/bin/dscl . -create "/Users/$CONSOLE" RealName "$NEW" >/dev/null 2>&1; then
    /bin/rm -f "$SAVE"
    printf '%s\n' "FATAL: could not set RealName" >&2
    exit 1
  fi
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
  /usr/bin/nohup /bin/bash "$0" --watch >/dev/null 2>&1 &
  printf '%s\n' "name-watcher pid $!"
  exit 0
fi

if [ "${1:-}" != "--watch" ]; then
  printf '%s\n' "Usage: $0 --start-from DIR | --restore" >&2
  exit 1
fi

appeared=0
waited=0
while [ "$waited" -lt 180 ]; do
  if zoom_running; then
    appeared=1
    break
  fi
  /bin/sleep 1
  waited=$((waited + 1))
done

if [ "$appeared" -eq 1 ]; then
  while zoom_running; do
    /bin/sleep 2
  done
fi

restore_realname
exit 0
