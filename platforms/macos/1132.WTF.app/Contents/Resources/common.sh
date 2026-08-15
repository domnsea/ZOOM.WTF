#!/bin/bash

PRODUCT="1132.WTF"
SUPPORT_ROOT="$HOME/Library/Application Support/1132.WTF"
ACTIVE_STATE="$SUPPORT_ROOT/active"
LOG_DIR="$HOME/Library/Logs/1132.WTF"
LOG_FILE="$LOG_DIR/launch.log"
LOCK_DIR="$SUPPORT_ROOT/launcher.lock"

mkdir -p "$SUPPORT_ROOT" "$LOG_DIR"
touch "$LOG_FILE"
chmod 700 "$SUPPORT_ROOT" "$LOG_DIR" 2>/dev/null || true
chmod 600 "$LOG_FILE" 2>/dev/null || true

log_line() {
  printf '%s | %s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "$LOG_FILE"
}

show_dialog() {
  local title="$1"
  local message="$2"
  local icon_kind="${3:-note}"
  /usr/bin/osascript - "$title" "$message" "$icon_kind" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  set theTitle to item 1 of argv
  set theMessage to item 2 of argv
  set theIcon to item 3 of argv
  if theIcon is "stop" then
    display dialog theMessage with title theTitle buttons {"OK"} default button "OK" with icon stop
  else
    display dialog theMessage with title theTitle buttons {"OK"} default button "OK" with icon note
  end if
end run
APPLESCRIPT
}

notify_user() {
  local title="$1"
  local message="$2"
  /usr/bin/osascript - "$title" "$message" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

find_zoom_app() {
  local candidate
  for candidate in "/Applications/zoom.us.app" "$HOME/Applications/zoom.us.app" "/Applications/Zoom Workplace.app" "$HOME/Applications/Zoom Workplace.app"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

zoom_processes_running() {
  local uid
  uid="$(id -u)"
  /bin/ps -axo uid=,command= | /usr/bin/awk -v uid="$uid" '
    $1 == uid {
      line=$0
      low=tolower(line)
      if (index(low,"/zoom.us.app/") || index(low,"/zoom workplace.app/") || index(low,"zoomautoupdater")) { found=1 }
    }
    END { exit(found ? 0 : 1) }
  '
}

stop_zoom_processes() {
  local i uid
  uid="$(id -u)"
  log_line "STOP" "Requesting clean Zoom shutdown for current desktop session"
  /usr/bin/osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
tell application "zoom.us" to quit
APPLESCRIPT
  for i in {1..20}; do
    if ! zoom_processes_running; then
      log_line "STOP" "Zoom stopped cleanly"
      return 0
    fi
    /bin/sleep 1
  done
  log_line "STOP" "Zoom still running after 20 seconds; sending TERM"
  /bin/ps -axo pid=,uid=,command= | /usr/bin/awk -v uid="$uid" '
    $2 == uid {
      line=$0
      low=tolower(line)
      if (index(low,"/zoom.us.app/") || index(low,"/zoom workplace.app/") || index(low,"zoomautoupdater")) print $1
    }
  ' | while read -r pid; do
    [[ -n "$pid" ]] && /bin/kill -TERM "$pid" 2>/dev/null || true
  done
  for i in {1..10}; do
    if ! zoom_processes_running; then
      log_line "STOP" "Zoom stopped after TERM"
      return 0
    fi
    /bin/sleep 1
  done
  log_line "STOP" "Zoom still running; refusing unsafe profile swap"
  return 1
}

# Collect exact and discovered Zoom-owned profile locations under the current user.
collect_zoom_targets() {
  local output="$1"
  : > "$output"

  cat >> "$output" <<'TARGETS'
Library/Application Support/zoom.us
Library/Application Support/Zoom
Library/Caches/us.zoom.xos
Library/Caches/zoom.us
Library/Caches/us.zoom.ZoomAutoUpdater
Library/Preferences/us.zoom.xos.plist
Library/Preferences/zoom.us.plist
Library/Preferences/ZoomChat.plist
Library/Preferences/us.zoom.ZoomAutoUpdater.plist
Library/Preferences/us.zoom.airhost.plist
Library/Logs/zoom.us
Library/Saved Application State/us.zoom.xos.savedState
Library/WebKit/us.zoom.xos
Library/HTTPStorages/us.zoom.xos
Library/HTTPStorages/us.zoom.xos.binarycookies
Library/Cookies/us.zoom.xos.binarycookies
Library/Containers/us.zoom.xos
Library/Containers/us.zoom.ZoomAutoUpdater
Library/Group Containers/BJ4HAAB9B3.ZoomClient3rd
TARGETS

  local parent base rel
  for parent in \
    "$HOME/Library/Application Support" \
    "$HOME/Library/Caches" \
    "$HOME/Library/Preferences" \
    "$HOME/Library/Logs" \
    "$HOME/Library/Saved Application State" \
    "$HOME/Library/WebKit" \
    "$HOME/Library/HTTPStorages" \
    "$HOME/Library/Cookies" \
    "$HOME/Library/Containers" \
    "$HOME/Library/Group Containers"; do
    [[ -d "$parent" ]] || continue
    while IFS= read -r base; do
      [[ -n "$base" ]] || continue
      rel="${parent#$HOME/}/$base"
      printf '%s\n' "$rel" >> "$output"
    done < <(/usr/bin/find "$parent" -mindepth 1 -maxdepth 1 \( -iname '*zoom*' -o -iname 'BJ4HAAB9B3.ZoomClient3rd' \) -exec basename '{}' \; 2>/dev/null)
  done

  /usr/bin/awk 'NF && !seen[$0]++' "$output" > "$output.tmp"
  /bin/mv "$output.tmp" "$output"
}

kill_preferences_cache() {
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
  /bin/sleep 1
}
