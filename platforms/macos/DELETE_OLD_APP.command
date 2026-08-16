#!/bin/bash
# The old Zoom.WTF in /Applications is owned by admin. Force Quit does not
# unlock it. This asks for the Mac password and deletes that copy only.

set -u

DEST="/Applications/1132.WTF.app"

printf '%s\n' "=== Delete the locked old 1132.WTF in Applications ==="
printf '%s\n' ""

if [ ! -d "$DEST" ]; then
  printf '%s\n' "Nothing to delete. /Applications/1132.WTF.app is already gone."
  printf '%s\n' "Now run INSTALL_TO_APPLICATIONS.command"
  exit 0
fi

if [ -f "$DEST/Contents/MacOS/applet" ]; then
  printf '%s\n' "This is the OLD Zoom.WTF applet. It must go."
fi

printf '%s\n' "Type your Mac password. Nothing shows."
if /usr/bin/sudo -p "Password: " /bin/bash -c "/usr/bin/killall -9 applet 1132.WTF 2>/dev/null || true; /bin/rm -rf '$DEST'"; then
  printf '%s\n' "STEP 1 - Old app deleted."
  printf '%s\n' "STEP 2 - Run INSTALL_TO_APPLICATIONS.command"
  printf '%s\n' "LAUNCH"
else
  printf '%s\n' "Password refused, or it failed."
  printf '%s\n' "Paste this in Terminal instead:"
  printf '%s\n' "  sudo rm -rf /Applications/1132.WTF.app"
  exit 1
fi
