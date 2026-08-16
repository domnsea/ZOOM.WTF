#!/bin/bash
# Emergency recovery from the last working v9 public release.
# Use this if the Mac restarts or cleanup is interrupted.
set -u
SUPPORT="$HOME/Library/Application Support/1132.WTF"
STATE="$SUPPORT/active"
LOG="$HOME/Library/Logs/1132.WTF/launch.log"
ROOT="$(cd "$(dirname "$0")" && pwd -P)"
RESTORE="$ROOT/1132.WTF.app/Contents/Resources/restore_profile.sh"
mkdir -p "$(dirname "$LOG")"
printf '%s | RECOVERY | START | public_release=YES recovery_requested=YES\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG"
if [[ ! -f "$RESTORE" ]]; then
  printf '%s\n' "The restore script is missing. Re-extract the ZIP and keep the folder together."
  exit 66
fi
SETNAME="$ROOT/1132.WTF.app/Contents/Resources/1132wtf-setname.sh"
if [[ -d "$STATE" ]]; then
  /bin/bash "$RESTORE" "$STATE" "manual-recovery"
  status=$?
else
  printf '%s\n' "There is no active temporary Zoom profile. Your regular Zoom profile is already in place."
  status=0
fi
if [[ -f "$SETNAME" ]]; then
  /usr/bin/sudo -p "Password: " /bin/bash "$SETNAME" --restore >/dev/null 2>&1 || true
fi
/usr/bin/open -R "$LOG" >/dev/null 2>&1 || true
exit "$status"
