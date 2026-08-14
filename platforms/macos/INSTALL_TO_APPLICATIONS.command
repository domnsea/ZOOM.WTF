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

printf '%s\n' "Installed: $DEST"
printf '%s\n' "Opening it now."
printf '%s\n' ""

if open "$DEST"; then
  printf '%s\n' "If a dialog still says the author cannot be verified:"
  printf '%s\n' "  1. Click Done, not Move to Trash"
  printf '%s\n' "  2. System Settings → Privacy & Security"
  printf '%s\n' "  3. Scroll down and click Open Anyway"
else
  printf '%s\n' "macOS blocked the open. Do this:"
  printf '%s\n' "  System Settings → Privacy & Security → Open Anyway"
  printf '%s\n' "or right-click $DEST in Finder and choose Open."
fi

read -r -p "Press Return to close. " _
