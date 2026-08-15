#!/bin/bash
# Stop 1132.WTF from running at login.
set -u

for BUNDLE_ID in wtf.fix1132.mac.21 wtf.fix1132.mac.20 wtf.fix1132.mac.19 wtf.fix1132.mac.18 wtf.fix1132.mac.17 wtf.fix1132.mac.16 wtf.fix1132.mac.15 wtf.fix1132.mac.14 wtf.fix1132.mac.13 wtf.fix1132.mac.12 wtf.fix1132.mac; do
  PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
  /bin/launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 ||
    /bin/launchctl unload "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
done

/usr/bin/osascript -e 'display dialog "1132.WTF will no longer run at login." buttons {"OK"} default button "OK" with title "1132.WTF"' >/dev/null 2>&1 ||
  printf '%s\n' "1132.WTF will no longer run at login."
