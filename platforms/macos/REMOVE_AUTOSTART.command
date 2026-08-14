#!/bin/bash
# Stop 1132.WTF from running at login.
set -u

BUNDLE_ID="wtf.fix1132.mac"
PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

/bin/launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 ||
  /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

/usr/bin/osascript -e 'display dialog "1132.WTF will no longer run at login." buttons {"OK"} default button "OK" with title "1132.WTF"' >/dev/null 2>&1 ||
  printf '%s\n' "1132.WTF will no longer run at login."
