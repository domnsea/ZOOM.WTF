#!/bin/bash
# Remove 1132.WTF completely: the app, the login item, and its own data.
# Zoom is not touched, and identity backups are kept unless you say otherwise.

set -u

APP_NAME="1132.WTF"
BUNDLE_ID="wtf.fix1132.mac"
SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

printf '%s\n' "=== Uninstall $APP_NAME ==="
printf '%s\n' ""

/bin/launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 ||
  /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"
printf '%s\n' "Login item removed."

if [ -d "/Applications/$APP_NAME.app" ]; then
  rm -rf "/Applications/$APP_NAME.app" && printf '%s\n' "App removed from /Applications."
fi

printf '%s\n' ""
printf '%s\n' "Throwaway accounts (wtf1132a, wtf1132b, wtf1132c) are not removed here."
printf '%s\n' "Delete any you still have in System Settings > Users & Groups."
printf '%s\n' ""
printf '%s\n' "Identity backups are in:"
printf '%s\n' "  $SUPPORT_DIR/backups"
printf '%s\n' ""
read -r -p "Delete backups and logs too? [y/N] " answer
case "$answer" in
  y | Y)
    rm -rf "$SUPPORT_DIR" "$LOG_DIR"
    printf '%s\n' "Backups and logs deleted."
    ;;
  *)
    printf '%s\n' "Kept: $SUPPORT_DIR and $LOG_DIR"
    ;;
esac

printf '%s\n' ""
printf '%s\n' "Done."
read -r -p "Press Return to close. " _
