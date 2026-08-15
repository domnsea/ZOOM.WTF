#!/bin/bash
# Remove 1132.WTF completely: the app, the login item, and its own data.
# Zoom is not touched, and identity backups are kept unless you say otherwise.

set -u

APP_NAME="1132.WTF"
BUNDLE_ID="wtf.fix1132.mac.22"
SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
OLD_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.plist"
OLD12_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.12.plist"
OLD13_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.13.plist"
OLD14_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.14.plist"
OLD15_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.15.plist"
OLD16_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.16.plist"
OLD17_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.17.plist"
OLD18_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.18.plist"
OLD19_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.19.plist"
OLD20_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.20.plist"
OLD21_PLIST="$HOME/Library/LaunchAgents/wtf.fix1132.mac.21.plist"

printf '%s\n' "=== Uninstall $APP_NAME ==="
printf '%s\n' ""

for item in "$PLIST" "$OLD_PLIST" "$OLD12_PLIST" "$OLD13_PLIST" "$OLD14_PLIST" "$OLD15_PLIST" "$OLD16_PLIST" "$OLD17_PLIST" "$OLD18_PLIST" "$OLD19_PLIST" "$OLD20_PLIST" "$OLD21_PLIST"; do
  /bin/launchctl bootout "gui/$(id -u)" "$item" >/dev/null 2>&1 ||
    /bin/launchctl unload "$item" >/dev/null 2>&1 || true
  rm -f "$item"
done
printf '%s\n' "Login item removed."

if [ -d "/Applications/$APP_NAME.app" ]; then
  rm -rf "/Applications/$APP_NAME.app" && printf '%s\n' "App removed from /Applications."
fi
if [ -d "/Library/Application Support/1132.WTF/zoom-6.3.11" ]; then
  rm -rf "/Library/Application Support/1132.WTF/zoom-6.3.11" && printf '%s\n' "Cached Zoom 6.3.11 removed."
fi

printf '%s\n' ""
printf '%s\n' "Hidden throwaway Zoom users from this app are deleted when Zoom quits."
printf '%s\n' "If one is still listed in System Settings > Users & Groups, delete it."
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
