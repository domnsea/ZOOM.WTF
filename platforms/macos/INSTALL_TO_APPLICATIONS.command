#!/bin/bash
# Copy 1132.WTF.app into /Applications and clear the quarantine flag that
# macOS adds to anything extracted from a downloaded zip.

set -u

APP_NAME="1132.WTF"
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$HERE/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

printf '%s\n' "=== $APP_NAME installer ==="

if [ ! -d "$SOURCE" ]; then
  printf '%s\n' "Cannot find $APP_NAME.app next to this script."
  printf '%s\n' "Extract the whole package and run this again."
  read -r -p "Press Return to close. " _
  exit 1
fi

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

chmod +x "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
chmod +x "$DEST/Contents/Resources/1132wtf-engine.sh" 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

printf '%s\n' "Installed: $DEST"
printf '%s\n' ""
printf '%s\n' "Opening it now. If macOS still complains that it cannot check the app,"
printf '%s\n' "right-click it in Applications and choose Open the first time."
open "$DEST" 2>/dev/null || true

read -r -p "Press Return to close. " _
