#!/bin/bash
# Unlock the throwaway login keychain in THIS process, then exec Zoom.
# A keychain created in an earlier sudo is invisible to Zoom — that is
# why it said none were found.
set -u
PASS="${1:-}"
BIN="${2:-}"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  printf '%s\n' "run_zoom_with_keychain: Zoom binary missing" >&2
  exit 69
fi

kcdir="${HOME}/Library/Keychains"
kc="$kcdir/login.keychain-db"
[ -f "$kc" ] || kc="$kcdir/login.keychain"
if [ ! -f "$kc" ]; then
  printf '%s\n' "run_zoom_with_keychain: no login keychain under $kcdir" >&2
  exit 72
fi

/usr/bin/security default-keychain -d user -s "$kc" >/dev/null 2>&1 || true
/usr/bin/security list-keychains -d user -s "$kc" /Library/Keychains/System.keychain >/dev/null 2>&1 || true
if [ -n "$PASS" ]; then
  /usr/bin/security unlock-keychain -p "$PASS" "$kc" >/dev/null 2>&1 || true
else
  /usr/bin/security unlock-keychain -p "" "$kc" >/dev/null 2>&1 || true
fi
/usr/bin/security set-keychain-settings -u "$kc" >/dev/null 2>&1 || true

exec "$BIN"
