#!/bin/bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SELF="$SCRIPT_DIR/$(basename "$0")"

if [ "$(id -u)" -ne 0 ]; then
  SELF_Q="$(printf '%s' "$SELF" | sed "s/'/'\\''/g")"
  ARG1_Q="$(printf '%s' "${1:-}" | sed "s/'/'\\''/g")"
  ARG2_Q="$(printf '%s' "${2:-}" | sed "s/'/'\\''/g")"
  /usr/bin/osascript -e "do shell script \"/bin/bash '$SELF_Q' '$ARG1_Q' '$ARG2_Q'\" with administrator privileges"
  exit $?
fi

CONSOLE_USER="$(/usr/bin/stat -f %Su /dev/console 2>/dev/null || true)"
CONSOLE_HOME="$(/usr/bin/dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
[ -n "$CONSOLE_HOME" ] || CONSOLE_HOME="/Users/$CONSOLE_USER"
export HOME="$CONSOLE_HOME"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

STATE_DIR="${1:-$ACTIVE_STATE}"
REASON="${2:-manual}"
BACKUP_DIR="$STATE_DIR/backup"
MANIFEST="$STATE_DIR/original-manifest.txt"
TARGETS_FILE="$STATE_DIR/targets.txt"
QUARANTINE="$STATE_DIR/quarantine"

log_line "RESTORE" "START reason=$REASON"

if [[ ! -d "$STATE_DIR" ]]; then
  log_line "RESTORE" "No active state; nothing to restore"
  exit 0
fi

TEMP_USER="$(/usr/bin/tr -d '\r\n' <"$STATE_DIR/temp.user" 2>/dev/null || true)"
case "$TEMP_USER" in
  "" | "$CONSOLE_USER" | root | daemon | nobody) ;;
  *)
    /usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
    /usr/sbin/sysadminctl -deleteUser "$TEMP_USER" >/dev/null 2>&1 || true
    /bin/rm -rf "/Users/$TEMP_USER" >/dev/null 2>&1 || true
    log_line "RESTORE" "deleted throwaway user"
    ;;
esac

/usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost >/dev/null 2>&1 || true
/bin/sleep 1

restore_network "$STATE_DIR"

kill_preferences_cache
mkdir -p "$QUARANTINE"

# Delete the disposable profile created by this run. Re-scan to catch new Zoom files.
CURRENT_TARGETS="$STATE_DIR/current-targets.txt"
collect_zoom_targets "$CURRENT_TARGETS"
if [[ -f "$TARGETS_FILE" ]]; then
  /bin/cat "$TARGETS_FILE" >> "$CURRENT_TARGETS"
fi
/usr/bin/awk 'NF && !seen[$0]++' "$CURRENT_TARGETS" > "$CURRENT_TARGETS.tmp"
/bin/mv "$CURRENT_TARGETS.tmp" "$CURRENT_TARGETS"

while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  current="$HOME/$rel"
  if [[ -e "$current" || -L "$current" ]]; then
    /bin/rm -rf "$current" 2>/dev/null || {
      log_line "RESTORE" "WARNING could not remove disposable path=$rel"
    }
    log_line "RESTORE" "ERASED disposable=$rel"
  fi
done < "$CURRENT_TARGETS"

RESTORED=0
FAILED=0
if [[ -f "$MANIFEST" ]]; then
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    source_path="$BACKUP_DIR/$rel"
    destination="$HOME/$rel"
    if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
      log_line "RESTORE" "WARNING backup missing path=$rel"
      FAILED=$((FAILED + 1))
      continue
    fi
    /bin/mkdir -p "$(dirname "$destination")"
    if [[ -e "$destination" || -L "$destination" ]]; then
      quarantine_path="$QUARANTINE/$rel"
      /bin/mkdir -p "$(dirname "$quarantine_path")"
      /bin/mv "$destination" "$quarantine_path" 2>/dev/null || /bin/rm -rf "$destination"
    fi
    if /bin/mv "$source_path" "$destination" 2>/dev/null; then
      RESTORED=$((RESTORED + 1))
      log_line "RESTORE" "RESTORED path=$rel"
    else
      FAILED=$((FAILED + 1))
      log_line "RESTORE" "FAILED path=$rel"
    fi
  done < "$MANIFEST"
fi

kill_preferences_cache

if [[ "$FAILED" -eq 0 ]]; then
  /bin/rm -rf "$STATE_DIR/runtime-home" "$STATE_DIR/runtime-tmp" "$QUARANTINE" "$CURRENT_TARGETS" 2>/dev/null || true
  /bin/rm -rf "$STATE_DIR" 2>/dev/null || true
  /bin/rmdir "$LOCK_DIR" 2>/dev/null || true
  log_line "RESTORE" "SUCCESS restored=$RESTORED failed=0 reason=$REASON"
  notify_user "1132.WTF" "Temporary Zoom profile deleted. Your regular Zoom profile was restored."
  exit 0
fi

log_line "RESTORE" "PARTIAL restored=$RESTORED failed=$FAILED recovery_state=PRESERVED"
show_dialog "1132.WTF Recovery Needed" "Your regular Zoom profile was only partially restored. Do not launch Zoom normally yet. Run RECOVERY - RESTORE REAL ZOOM.command and open OPEN_LOGS.command." "stop"
exit 74
