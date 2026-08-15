#!/bin/bash
# Copy 1132.WTF.app into /Applications, strip the download quarantine, and
# ad-hoc sign it so Gatekeeper will launch it without a paid Developer ID.

set -u

APP_NAME="1132.WTF"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
# allow-macos.sh sits next to this installer in the zip.
# shellcheck disable=SC1091
. "$HERE/allow-macos.sh"

printf '%s\n' "=== $APP_NAME installer ==="

if [ ! -d "$SOURCE" ]; then
  printf '%s\n' "Cannot find $APP_NAME.app next to this script."
  printf '%s\n' "Extract the whole package (not just the .app) and run this again."
  read -r -p "Press Return to close. " _
  exit 1
fi

printf '%s\n' "Clearing the download flag on this folder..."
allow_tree "$HERE"

if [ -d "$DEST" ]; then
  printf '%s\n' "Replacing the existing copy in /Applications..."
  rm -rf "$DEST" || {
    printf '%s\n' "Could not remove $DEST. Quit $APP_NAME and try again."
    read -r -p "Press Return to close. " _
    exit 1
  }
fi

if ! cp -R "$SOURCE" "$DEST"; then
  printf '%s\n' "Could not copy into /Applications."
  read -r -p "Press Return to close. " _
  exit 1
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

# Close this window. Do not sit on "Press Return" forever.
/usr/bin/osascript -e 'tell application "Terminal" to close (every window whose name contains "INSTALL_TO_APPLICATIONS")' >/dev/null 2>&1 || true
exit 0

