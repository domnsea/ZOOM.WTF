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

# Read one state file. Missing files must not print "No such file" and
# must not abort a leftover STEP 1 recovery.
read_state_line() {
  local f="${1:-}"
  [ -n "$f" ] && [ -f "$f" ] || return 0
  /usr/bin/tr -d '\r\n' <"$f"
}

show_dialog() {
  local title="$1"
  local message="$2"
  local icon_kind="${3:-note}"
  printf '\n=== %s ===\n%s\n\n' "$title" "$message"
  if [ "$icon_kind" != "stop" ] && [ -t 0 ]; then
    printf '%s' "Press Return. "
    read -r _ || true
    printf '\n'
  fi
}

notify_user() {
  printf '%s — %s\n' "$1" "$2"
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
  uid="${CONSOLE_UID:-}"
  [ -n "$uid" ] || uid="$(/usr/bin/stat -f %u /dev/console 2>/dev/null || /usr/bin/id -u)"
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
# ~/.zoomus and us.zoom.config.plist hold the client device id 1132 keys off.
collect_zoom_targets() {
  local output="$1"
  : > "$output"

  cat >> "$output" <<'TARGETS'
.zoomus
Library/Application Support/zoom.us
Library/Application Support/Zoom
Library/Application Support/us.zoom.xos
Library/Application Support/ZoomChat
Library/Application Support/ZoomAutoUpdater
Library/Caches/us.zoom.xos
Library/Caches/zoom.us
Library/Caches/com.zoom.us
Library/Caches/us.zoom.ZoomAutoUpdater
Library/Caches/us.zoom.updater
Library/Caches/Zoom
Library/Preferences/us.zoom.xos.plist
Library/Preferences/us.zoom.config.plist
Library/Preferences/zoom.us.plist
Library/Preferences/ZoomChat.plist
Library/Preferences/us.zoom.ZoomAutoUpdater.plist
Library/Preferences/us.zoom.updater.plist
Library/Preferences/us.zoom.airhost.plist
Library/Logs/zoom.us
Library/Logs/Zoom
Library/Saved Application State/us.zoom.xos.savedState
Library/WebKit/us.zoom.xos
Library/WebKit/com.zoom.us
Library/HTTPStorages/us.zoom.xos
Library/HTTPStorages/us.zoom.xos.binarycookies
Library/Cookies/us.zoom.xos.binarycookies
Library/Containers/us.zoom.xos
Library/Containers/com.zoom.us
Library/Containers/us.zoom.ZoomAutoUpdater
Library/Group Containers/BJ4HAAB9B3.ZoomClient3rd
TARGETS

  local parent base rel
  for parent in \
    "$HOME/Library/Application Support" \
    "$HOME/Library/Caches" \
    "$HOME/Library/Preferences" \
    "$HOME/Library/Preferences/ByHost" \
    "$HOME/Library/Logs" \
    "$HOME/Library/Saved Application State" \
    "$HOME/Library/WebKit" \
    "$HOME/Library/HTTPStorages" \
    "$HOME/Library/Cookies" \
    "$HOME/Library/Containers" \
    "$HOME/Library/Group Containers" \
    "$HOME/Library/LaunchAgents"; do
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

# Anything collect_zoom_targets missed: Zoom.tbd, stray .zoomus, /var/folders
# caches. 1132 survives when these stay in the real home while Zoom ignores HOME=.
sweep_stray_zoom_identity() {
  local dest="$1"
  local path tag uid
  uid="${CONSOLE_UID:-$(/usr/bin/id -u)}"
  /bin/mkdir -p "$dest"
  : >>"$dest/stray.list"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      *"/1132.WTF"*|*"/wtf.fix1132"*) continue ;;
    esac
    [[ -e "$path" || -L "$path" ]] || continue
    tag="$(printf '%s' "$path" | /usr/bin/tr '/ ' '__')"
    if /bin/mv "$path" "$dest/$tag" 2>/dev/null; then
      printf '%s\t%s\n' "$path" "$tag" >> "$dest/stray.list"
      log_line "SWEEP" "moved stray $path"
    else
      /bin/rm -rf "$path" 2>/dev/null || true
      log_line "SWEEP" "removed stray $path"
    fi
  done < <(
    /usr/bin/find "$HOME" -maxdepth 2 \( -name '.zoomus' -o -name 'Zoom.tbd' -o -iname 'zoom.tbd' \) 2>/dev/null
    /usr/bin/find "$HOME/Library" -iname 'Zoom.tbd' 2>/dev/null
    /usr/bin/find /var/folders -user "$uid" \( -iname '*zoom*' -o -iname 'us.zoom*' \) -maxdepth 6 2>/dev/null
  )
}

restore_stray_zoom_identity() {
  local dest="$1/stray-zoom"
  local orig tag
  [ -f "$dest/stray.list" ] || return 0
  while IFS="$(printf '\t')" read -r orig tag; do
    [ -n "$orig" ] && [ -n "$tag" ] || continue
    if [ -e "$dest/$tag" ] || [ -L "$dest/$tag" ]; then
      /bin/mkdir -p "$(/usr/bin/dirname "$orig")"
      /bin/mv "$dest/$tag" "$orig" 2>/dev/null || true
      log_line "SWEEP" "restored stray $orig"
    fi
  done <"$dest/stray.list"
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
  /bin/mkdir -p "$state"
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
  computer="$(read_state_line "$state/net.computer")"
  localn="$(read_state_line "$state/net.localhost")"
  host="$(read_state_line "$state/net.hostname")"
  [ -n "$computer" ] && /usr/sbin/scutil --set ComputerName "$computer" >/dev/null 2>&1 || true
  [ -n "$localn" ] && /usr/sbin/scutil --set LocalHostName "$localn" >/dev/null 2>&1 || true
  if [ -n "$host" ]; then
    /usr/sbin/scutil --set HostName "$host" >/dev/null 2>&1 || true
  fi
  restore_isolated_network "$state"
  if [ -n "$computer$localn$host" ] || [ -f "$state/net.ifaces" ] || [ -f "$state/net.services" ]; then
    log_line "NET" "computer name restored"
  fi
}

net_service_for_iface() {
  /usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk -v d="${1:-}" '
    /Hardware Port:/ {port=$0; sub(/^Hardware Port: /,"",port)}
    $1=="Device:" && $2==d {print port; exit}
  '
}

# Home Wi-Fi + IPv6 can still carry 1132 after IPv4 changes. Keep only the
# current default service and turn IPv6 off for this session.
isolate_network_path() {
  local state="$1"
  local keep iface service name enabled v6info v6
  iface="$(net_iface)"
  keep="$(net_service_for_iface "$iface")"
  printf '%s\n' "$keep" >"$state/net.keep_service"
  : >"$state/net.services"
  while IFS= read -r name; do
    case "$name" in
      "" | "An asterisk"*) continue ;;
    esac
    enabled=on
    case "$name" in
      \**) name="${name#\* }"; enabled=off ;;
    esac
    [ -n "$name" ] || continue
    v6info="$(/usr/sbin/networksetup -getinfo "$name" 2>/dev/null || true)"
    v6=automatic
    printf '%s\n' "$v6info" | /usr/bin/grep -qi 'IPv6: Off' && v6=off
    printf '%s\t%s\t%s\n' "$name" "$enabled" "$v6" >>"$state/net.services"
    /usr/sbin/networksetup -setv6off "$name" >/dev/null 2>&1 || true
    if [ -n "$keep" ] && [ "$name" != "$keep" ] && [ "$enabled" = "on" ]; then
      /usr/sbin/networksetup -setnetworkserviceenabled "$name" off >/dev/null 2>&1 || true
      log_line "NET" "disabled extra service=$name keep=$keep"
    fi
  done < <(/usr/sbin/networksetup -listallnetworkservices 2>/dev/null)
  log_line "NET" "IPv6 off; only $keep left up"
}

restore_isolated_network() {
  local state="$1"
  local name enabled v6
  [ -f "$state/net.services" ] || return 0
  while IFS="$(printf '\t')" read -r name enabled v6; do
    [ -n "$name" ] || continue
    if [ "$enabled" = "on" ]; then
      /usr/sbin/networksetup -setnetworkserviceenabled "$name" on >/dev/null 2>&1 || true
    fi
    if [ "$v6" = "off" ]; then
      /usr/sbin/networksetup -setv6off "$name" >/dev/null 2>&1 || true
    else
      /usr/sbin/networksetup -setv6automatic "$name" >/dev/null 2>&1 || true
    fi
  done <"$state/net.services"
  log_line "NET" "network services and IPv6 restored"
}

# Admin `do shell script` runs as root in a session that often has no
# working HTTPS/DNS. Look up the public IP as the logged-in desktop user.
as_console_bash() {
  local snippet="$1"
  if [ "$(id -u)" -eq 0 ] && [ -n "${CONSOLE_UID:-}" ] && [ -n "${CONSOLE_USER:-}" ]; then
    /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/sudo -u "$CONSOLE_USER" -H \
      /usr/bin/env HOME="${CONSOLE_HOME:-/Users/$CONSOLE_USER}" /bin/bash -c "$snippet"
  else
    /bin/bash -c "$snippet"
  fi
}

# One shot. Prints a public IPv4, or an IPv6 if that is all the network has.
_public_ip_snippet() {
  cat <<'SNIP'
ip=""
try4() { /usr/bin/curl -4 -fsS --connect-timeout 3 --max-time 6 "$1" 2>/dev/null; }
for url in \
  https://api.ipify.org \
  https://ipv4.icanhazip.com \
  https://checkip.amazonaws.com \
  https://ifconfig.me/ip \
  https://icanhazip.com \
  https://ipinfo.io/ip
do
  ip="$(try4 "$url" | /usr/bin/tr -d '[:space:]')"
  case "$ip" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$ip"; exit 0 ;;
  esac
done
if [ -x /usr/bin/dig ]; then
  ip="$(/usr/bin/dig +short +time=3 +tries=1 myip.opendns.com @resolver1.opendns.com 2>/dev/null | /usr/bin/tr -d '[:space:]')"
  case "$ip" in
    [0-9]*.[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$ip"; exit 0 ;;
  esac
fi
ip="$(/usr/bin/curl -6 -fsS --connect-timeout 3 --max-time 6 https://api64.ipify.org 2>/dev/null | /usr/bin/tr -d '[:space:]')"
[ -n "$ip" ] && printf '%s\n' "$ip"
SNIP
}

public_ip() {
  as_console_bash "$(_public_ip_snippet)" 2>/dev/null || true
}

public_ipv6() {
  as_console_bash '/usr/bin/curl -6 -fsS --connect-timeout 3 --max-time 6 https://api64.ipify.org 2>/dev/null || /usr/bin/curl -6 -fsS --connect-timeout 3 --max-time 6 https://ifconfig.me/ip 2>/dev/null || true' 2>/dev/null || true
}

# Hotspot NAT is often not up on the first try. Keep asking for ~30s.
wait_for_public_ip() {
  local tries=0 ip
  while [ "$tries" -lt 10 ]; do
    ip="$(public_ip | /usr/bin/tr -d '[:space:]')"
    if [ -n "$ip" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
    tries=$((tries + 1))
    /bin/sleep 3
  done
  return 1
}

# Console uid for launchctl bootout. Launch/restore set CONSOLE_UID;
# fall back to the logged-in desktop if they did not.
console_uid() {
  if [ -n "${CONSOLE_UID:-}" ]; then
    printf '%s' "$CONSOLE_UID"
    return 0
  fi
  /usr/bin/stat -f %u /dev/console 2>/dev/null || /usr/bin/id -u
}

# ZoomDaemon and the system LaunchDaemons keep a machine token for THIS
# Mac even after the user profile is gone. Unload them before Zoom opens.
bootout_zoom_system_jobs() {
  local plist uid
  uid="$(console_uid)"
  /usr/bin/killall -9 ZoomDaemon us.zoom.ZoomDaemon ZoomUpdater us.zoom.updater >/dev/null 2>&1 || true
  for plist in /Library/LaunchDaemons/us.zoom*.plist /Library/LaunchDaemons/*[Zz]oom*.plist; do
    [ -f "$plist" ] || continue
    /bin/launchctl bootout system "$plist" >/dev/null 2>&1 ||
      /bin/launchctl unload "$plist" >/dev/null 2>&1 || true
  done
  for plist in /Library/LaunchAgents/us.zoom*.plist /Library/LaunchAgents/*[Zz]oom*.plist; do
    [ -f "$plist" ] || continue
    /bin/launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 ||
      /bin/launchctl bootout system "$plist" >/dev/null 2>&1 ||
      /bin/launchctl unload "$plist" >/dev/null 2>&1 || true
  done
}

# Zoom also stores a machine id in the System keychain. Those items are
# deleted for this session (they cannot be moved). Regular Zoom recreates
# them after restore.
scrub_system_zoom_keychain() {
  local item n
  for item in \
    "Zoom Safe Meeting Storage" \
    "zoom.us" \
    "Zoom" \
    "us.zoom.xos" \
    "Zoom SSO" \
    "ZoomChat" \
    "ZoomAutoUpdater" \
    "us.zoom.updater" \
    "us.zoom.ZoomDaemon"
  do
    n=0
    while [ "$n" -lt 40 ]; do
      /usr/bin/security delete-generic-password -l "$item" /Library/Keychains/System.keychain >/dev/null 2>&1 || break
      n=$((n + 1))
    done
    n=0
    while [ "$n" -lt 40 ]; do
      /usr/bin/security delete-generic-password -s "$item" /Library/Keychains/System.keychain >/dev/null 2>&1 || break
      n=$((n + 1))
    done
  done
  log_line "STASH" "system keychain Zoom items removed"
}

stash_one_path() {
  local state="$1" src="$2"
  local dest="$state/stashed-apps"
  local tag
  [ -e "$src" ] || [ -L "$src" ] || return 0
  tag="$(printf '%s' "$src" | /usr/bin/tr '/ ' '__')"
  if /bin/mv "$src" "$dest/$tag" 2>/dev/null; then
    printf '%s\t%s\n' "$src" "$tag" >>"$state/stashed-apps.list"
    log_line "STASH" "hid $src"
    return 0
  fi
  log_line "STASH" "could not hide $src"
  return 1
}

# Hide machine-level Zoom tokens (daemon, /Library, /var/root). Do not
# hide Applications Zoom — STEP 1 opens that copy on a blank profile.
stash_system_zoom() {
  local state="$1"
  local dest="$state/stashed-apps"
  local src domain
  /bin/mkdir -p "$dest"
  : >"$state/stashed-apps.list"
  bootout_zoom_system_jobs
  for src in \
    "/Library/Application Support/zoom.us" \
    "/Library/Application Support/Zoom" \
    "/Library/Logs/zoom.us" \
    "/Library/PrivilegedHelperTools/us.zoom.ZoomDaemon" \
    "/Library/PrivilegedHelperTools/us.zoom.updater" \
    "/var/root/Library/Application Support/zoom.us" \
    "/var/root/Library/Application Support/Zoom" \
    "/var/root/Library/Logs/zoom.us" \
    "/var/root/.zoomus"
  do
    stash_one_path "$state" "$src"
  done
  for src in \
    /Library/LaunchDaemons/us.zoom*.plist \
    /Library/LaunchAgents/us.zoom*.plist \
    /Library/Preferences/us.zoom* \
    /Library/Preferences/zoom.us* \
    /Library/PrivilegedHelperTools/us.zoom* \
    /var/root/Library/Preferences/us.zoom* \
    /var/root/Library/Preferences/zoom.us* \
    /var/root/Library/Caches/us.zoom* \
    /var/root/Library/Caches/zoom.us*
  do
    stash_one_path "$state" "$src"
  done
  for domain in \
    us.zoom.xos \
    zoom.us \
    us.zoom.config \
    us.zoom.updater \
    us.zoom.ZoomAutoUpdater \
    us.zoom.pkginstall
  do
    /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
  done
  scrub_system_zoom_keychain
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
}

relink_zoom_helpers() {
  local state="$1"
  local orig base
  [ -f "$state/stashed-apps.list" ] || return 0
  while IFS="$(printf '\t')" read -r orig base; do
    case "$orig" in
      /Library/LaunchDaemons/*.plist)
        [ -f "$orig" ] || continue
        /bin/launchctl bootstrap system "$orig" >/dev/null 2>&1 ||
          /bin/launchctl load "$orig" >/dev/null 2>&1 || true
        log_line "STASH" "reloaded $orig"
        ;;
    esac
  done <"$state/stashed-apps.list"
}

restore_stashed_apps() {
  local state="$1"
  local dest="$state/stashed-apps"
  local orig base
  [ -f "$state/stashed-apps.list" ] || return 0
  while IFS="$(printf '\t')" read -r orig base; do
    [ -n "$orig" ] && [ -n "$base" ] || continue
    if [ -e "$dest/$base" ] || [ -L "$dest/$base" ]; then
      /bin/rm -rf "$orig" 2>/dev/null || true
      /bin/mkdir -p "$(/usr/bin/dirname "$orig")"
      /bin/mv "$dest/$base" "$orig" 2>/dev/null || true
      log_line "STASH" "restored $orig"
    fi
  done <"$state/stashed-apps.list"
  relink_zoom_helpers "$state"
}

# Hotspot first. Then a blank Zoom profile is created so Zoom's first
# packet is this address only. Extra NICs and IPv6 are turned off so
# the old home path cannot register. MAC is not spoofed.
require_new_public_ip() {
  local state="$1"
  local before after v6
  before="$(public_ip | /usr/bin/tr -d '[:space:]')"
  printf '%s\n' "$before" >"$state/ip.before"
  show_dialog "1132.WTF" "Connect ONLY a phone hotspot. Turn home Wi-Fi off.

A new Zoom profile is created after you click OK. That profile never sees your old IP. When you quit Zoom, the profile is deleted so regular Zoom never gets the hotspot address.

Current IP: ${before:-not read yet}" "note"
  after="$(wait_for_public_ip | /usr/bin/tr -d '[:space:]')"
  printf '%s\n' "$after" >"$state/ip.after"
  isolate_network_path "$state" || true
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" = "$after" ]; then
    log_line "NET" "public IP unchanged $after — still creating a blank profile on this path"
    show_dialog "1132.WTF" "IP is still $after. A blank Zoom profile will still be created on this network only. Turn home Wi-Fi off if the hotspot is USB." "note"
  elif [ -z "$after" ]; then
    log_line "NET" "public IP unread before=$before after=; blank profile on current path"
  else
    log_line "NET" "public IP ${before:-none} -> $after"
  fi
  v6="$(public_ipv6 | /usr/bin/tr -d '[:space:]')"
  if [ -n "$v6" ]; then
    log_line "NET" "IPv6 still visible $v6"
    show_dialog "1132.WTF" "IPv6 is still $v6. Turn off home Wi-Fi if you can. Opening the blank Zoom profile anyway." "note"
  fi
  return 0
}
