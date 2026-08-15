#!/bin/bash
# Copy 1132.WTF.app into /Applications, strip the download quarantine, and
# ad-hoc sign it so Gatekeeper will launch it without a paid Developer ID.
#
# An older Zoom.WTF applet is often already in /Applications and owned by
# root. A normal rm cannot replace it, so this installer asks for the Mac
# password and deletes that copy first.

set -u

APP_NAME="1132.WTF"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
# allow-macos.sh sits next to this installer in the zip.
# shellcheck disable=SC1091
. "$HERE/allow-macos.sh"

applescript_quote() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

run_admin() {
  local script
  script="$(applescript_quote "$1")"
  /usr/bin/osascript -e "do shell script \"$script\" with administrator privileges"
}

printf '%s\n' "=== $APP_NAME installer ==="

if [ ! -d "$SOURCE" ]; then
  printf '%s\n' "Cannot find $APP_NAME.app next to this script."
  printf '%s\n' "Extract the whole package (not just the .app) and run this again."
  read -r -p "Press Return to close. " _
  exit 1
fi

printf '%s\n' "Clearing the download flag on this folder..."
allow_tree "$HERE"

# The old Zoom.WTF was an AppleScript applet. If that is what is sitting in
# Applications, every launch from there is the old app — not this one.
if [ -f "$DEST/Contents/MacOS/applet" ] || [ -f "$DEST/Contents/Resources/Scripts/main.scpt" ]; then
  printf '%s\n' "The app in /Applications is the OLD Zoom.WTF (not this one)."
  printf '%s\n' "That is why the name never changed. Removing it."
fi

/usr/bin/killall -9 "1132.WTF" applet >/dev/null 2>&1 || true

if [ -d "$DEST" ]; then
  printf '%s\n' "Replacing the existing copy in /Applications..."
  if ! rm -rf "$DEST" 2>/dev/null; then
    printf '%s\n' "That copy is locked. macOS will ask for your password."
    if ! run_admin "/bin/rm -rf '$DEST'"; then
      printf '%s\n' "Password refused. The old app is still in /Applications."
      read -r -p "Press Return to close. " _
      exit 1
    fi
  fi
fi

if [ -d "$DEST" ]; then
  printf '%s\n' "Could not remove $DEST."
  read -r -p "Press Return to close. " _
  exit 1
fi

if ! cp -R "$SOURCE" "$DEST" 2>/dev/null; then
  printf '%s\n' "Need your password to copy into /Applications."
  if ! run_admin "/bin/cp -R '$SOURCE' '$DEST' && /usr/sbin/chown -R $(id -un):staff '$DEST'"; then
    printf '%s\n' "Could not copy into /Applications."
    read -r -p "Press Return to close. " _
    exit 1
  fi
fi

allow_target "$DEST"

printf '%s\n' "STEP 1 - Installed: $DEST"
printf '%s\n' "STEP 2 - Cleared the download block"
printf '%s\n' "LAUNCH - Opening 1132.WTF now"
printf '%s\n' ""

if open "$DEST"; then
  printf '%s\n' "If macOS still blocks it:"
  printf '%s\n' "  STEP 1 - Click Done (not Move to Trash)"
  printf '%s\n' "  STEP 2 - System Settings → Privacy & Security → Open Anyway"
  printf '%s\n' "  LAUNCH - Open 1132.WTF from Applications"
else
  printf '%s\n' "macOS blocked the open."
  printf '%s\n' "  STEP 1 - System Settings → Privacy & Security → Open Anyway"
  printf '%s\n' "  STEP 2 - Or right-click $DEST → Open"
  printf '%s\n' "  LAUNCH - Open 1132.WTF from Applications"
fi

/usr/bin/osascript -e 'tell application "Terminal" to close (every window whose name contains "INSTALL_TO_APPLICATIONS")' >/dev/null 2>&1 || true
exit 0
