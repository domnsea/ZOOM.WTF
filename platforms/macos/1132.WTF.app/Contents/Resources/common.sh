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

net_iface() {
  local d
  d="$(/usr/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  if [ -z "$d" ]; then
    d="$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk '
      /Hardware Port: Wi-Fi|Hardware Port: AirPort/ {want=1; next}
      want && $1=="Device:" {print $2; exit}
    ')"
  fi
  printf '%s' "$d"
}

net_wifi_iface() {
  /usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk '
    /Hardware Port: Wi-Fi|Hardware Port: AirPort/ {want=1; next}
    want && $1=="Device:" {print $2; exit}
  '
}

net_mac() {
  /sbin/ifconfig "${1:-}" 2>/dev/null | /usr/bin/awk '/ether /{print $2; exit}'
}

# Locally administered unicast MAC. Restored when Zoom quits.
net_random_mac() {
  printf '02:%02x:%02x:%02x:%02x:%02x' \
    $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

net_is_wifi() {
  local iface="$1"
  /usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk -v d="$iface" '
    /Hardware Port:/ {port=$0}
    $1=="Device:" && $2==d { if (port ~ /Wi-Fi|AirPort/) found=1 }
    END { exit(found ? 0 : 1) }
  '
}

net_set_mac() {
  local iface="$1" mac="$2"
  [ -n "$iface" ] && [ -n "$mac" ] || return 1
  if net_is_wifi "$iface"; then
    /usr/sbin/networksetup -setairportpower "$iface" off >/dev/null 2>&1 || true
    /bin/sleep 1
  fi
  /sbin/ifconfig "$iface" ether "$mac" >/dev/null 2>&1 ||
    /sbin/ifconfig "$iface" lladdr "$mac" >/dev/null 2>&1 || true
  if net_is_wifi "$iface"; then
    /usr/sbin/networksetup -setairportpower "$iface" on >/dev/null 2>&1 || true
    /bin/sleep 2
  fi
}

# Rotate the live interface MAC and the Mac computer name for this Zoom
# session. Does not rewrite the logic-board serial or hardware UUID.
save_and_rotate_network() {
  local state="$1"
  local iface wifi mac new got host
  : >"$state/net.ifaces"
  iface="$(net_iface)"
  wifi="$(net_wifi_iface)"
  /usr/sbin/scutil --get ComputerName 2>/dev/null >"$state/net.computer" || true
  /usr/sbin/scutil --get LocalHostName 2>/dev/null >"$state/net.localhost" || true
  /usr/sbin/scutil --get HostName 2>/dev/null >"$state/net.hostname" || true

  for iface in "$iface" "$wifi"; do
    [ -n "$iface" ] || continue
    mac="$(net_mac "$iface")"
    [ -n "$mac" ] || continue
    if /usr/bin/grep -q "^${iface}	" "$state/net.ifaces" 2>/dev/null; then
      continue
    fi
    printf '%s\t%s\n' "$iface" "$mac" >>"$state/net.ifaces"
    new="$(net_random_mac)"
    net_set_mac "$iface" "$new"
    got="$(net_mac "$iface")"
    if [ "$got" = "$new" ]; then
      log_line "NET" "MAC rotated iface=$iface from=$mac to=$new"
    else
      log_line "NET" "MAC unchanged iface=$iface hardware=$mac (this Mac locked the address)"
    fi
  done

  host="mac$(printf '%04d' $((RANDOM % 10000)))"
  /usr/sbin/scutil --set ComputerName "$host" >/dev/null 2>&1 || true
  /usr/sbin/scutil --set LocalHostName "$host" >/dev/null 2>&1 || true
  /usr/sbin/scutil --set HostName "$host" >/dev/null 2>&1 || true
  printf '%s\n' "$host" >"$state/net.new_host"
  log_line "NET" "hostname rotated to $host"
}

restore_network() {
  local state="$1"
  local iface mac computer localn host
  [ -d "$state" ] || return 0
  if [ -f "$state/net.ifaces" ]; then
    while IFS="$(printf '\t')" read -r iface mac; do
      [ -n "$iface" ] && [ -n "$mac" ] || continue
      net_set_mac "$iface" "$mac"
      log_line "NET" "MAC restored iface=$iface"
    done <"$state/net.ifaces"
  fi
  computer="$(/usr/bin/tr -d '\r\n' <"$state/net.computer" 2>/dev/null || true)"
  localn="$(/usr/bin/tr -d '\r\n' <"$state/net.localhost" 2>/dev/null || true)"
  host="$(/usr/bin/tr -d '\r\n' <"$state/net.hostname" 2>/dev/null || true)"
  [ -n "$computer" ] && /usr/sbin/scutil --set ComputerName "$computer" >/dev/null 2>&1 || true
  [ -n "$localn" ] && /usr/sbin/scutil --set LocalHostName "$localn" >/dev/null 2>&1 || true
  if [ -n "$host" ]; then
    /usr/sbin/scutil --set HostName "$host" >/dev/null 2>&1 || true
  fi
  log_line "NET" "computer name restored"
}

public_ip() {
  /usr/bin/curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null ||
    /usr/bin/curl -fsS --max-time 8 https://ifconfig.me/ip 2>/dev/null ||
    /usr/bin/curl -fsS --max-time 8 https://icanhazip.com 2>/dev/null ||
    true
}

# Hide the Zoom in Applications so Dock / Spotlight cannot open the
# 1132-tagged client during this session.
stash_system_zoom() {
  local state="$1"
  local dest="$state/stashed-apps"
  local app base
  /bin/mkdir -p "$dest"
  : >"$state/stashed-apps.list"
  for app in \
    "/Applications/zoom.us.app" \
    "/Applications/Zoom Workplace.app" \
    "$HOME/Applications/zoom.us.app" \
    "$HOME/Applications/Zoom Workplace.app"
  do
    [ -d "$app" ] || continue
    base="$(/usr/bin/basename "$app")"
    if /bin/mv "$app" "$dest/$base" 2>/dev/null; then
      printf '%s\t%s\n' "$app" "$base" >>"$state/stashed-apps.list"
      log_line "STASH" "hid $app"
    fi
  done
  if [ -d "/Library/Application Support/zoom.us" ]; then
    if /bin/mv "/Library/Application Support/zoom.us" "$dest/Library-Application-Support-zoom.us" 2>/dev/null; then
      printf '%s\t%s\n' "/Library/Application Support/zoom.us" "Library-Application-Support-zoom.us" >>"$state/stashed-apps.list"
      log_line "STASH" "hid /Library/Application Support/zoom.us"
    fi
  fi
}

restore_stashed_apps() {
  local state="$1"
  local dest="$state/stashed-apps"
  local orig base
  [ -f "$state/stashed-apps.list" ] || return 0
  while IFS="$(printf '\t')" read -r orig base; do
    [ -n "$orig" ] && [ -n "$base" ] || continue
    if [ -e "$dest/$base" ]; then
      /bin/rm -rf "$orig" 2>/dev/null || true
      /bin/mkdir -p "$(/usr/bin/dirname "$orig")"
      /bin/mv "$dest/$base" "$orig" 2>/dev/null || true
      log_line "STASH" "restored $orig"
    fi
  done <"$state/stashed-apps.list"
}

# 1132 after a new name / MAC / Zoom 6.3 is the public IP. Do not open Zoom
# on the same address.
require_new_public_ip() {
  local state="$1"
  local before after
  before="$(public_ip | /usr/bin/tr -d '[:space:]')"
  printf '%s\n' "$before" >"$state/ip.before"
  show_dialog "1132.WTF" "Public IP right now: ${before:-unknown}

A new name, MAC, and Zoom 6.3.11 still got 1132. That is this IP or this Mac.

Connect a phone hotspot — not the same Wi-Fi. Then click OK." "note"
  after="$(public_ip | /usr/bin/tr -d '[:space:]')"
  printf '%s\n' "$after" >"$state/ip.after"
  if [ -z "$before" ] || [ -z "$after" ]; then
    log_line "NET" "public IP unread before=$before after=$after"
    show_dialog "1132.WTF" "Could not read the public IP. Zoom was not opened. Connect a hotspot and run STEP 1 again." "stop"
    return 1
  fi
  if [ "$before" = "$after" ]; then
    log_line "NET" "public IP unchanged $after"
    show_dialog "1132.WTF" "Still $after. Same IP = 1132. Zoom was not opened. Connect a phone hotspot and run STEP 1 again." "stop"
    return 1
  fi
  log_line "NET" "public IP $before -> $after"
  return 0
}
