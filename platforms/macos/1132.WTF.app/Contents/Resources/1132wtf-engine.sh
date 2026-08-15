#!/bin/bash
#
# 1132.WTF engine for macOS
# Implements the levels described in docs/ENGINE.md.
#
# Usage: 1132wtf-engine.sh <verb> [argument]
#   status | fix | deep-fix | browser | restore
#   autostart-on | autostart-off | logs
#
# Shell based on purpose: it is architecture neutral, so one copy runs on both
# Intel and Apple Silicon with no build step and no notarised binary.

set -u
set -o pipefail

APP_NAME="1132.WTF"
APP_VERSION="1.0.16"
BUNDLE_ID="wtf.fix1132.mac.16"

SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
BACKUP_DIR="$SUPPORT_DIR/backups"
# Empty Zoom profile used only for the launch after a reset. Recreated every
# fix so Zoom cannot reopen the leftover name, rooms, or signed-in account.
CLEAN_PROFILE_DIR="$SUPPORT_DIR/zoom-clean"
SLOT_FILE="$SUPPORT_DIR/slot.txt"
LAST_RUN_FILE="$SUPPORT_DIR/lastrun.txt"
LOCK_DIR="$SUPPORT_DIR/run.lock"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

# Throwaway rotation accounts. macOS short names must be lowercase and have no
# dots. The prefix is reserved so rotation can never touch a real account.
SLOT_PREFIX="wtf1132"
SLOT_NAMES=("wtf1132a" "wtf1132b" "wtf1132c")

ZOOM_BUNDLE_ID="us.zoom.xos"

mkdir -p "$SUPPORT_DIR" "$LOG_DIR" "$BACKUP_DIR"
# The PID keeps two runs started inside the same second from sharing a log.
LOG_FILE="$LOG_DIR/engine_$(date +%Y-%m-%d_%H%M%S)_$$.log"

# --------------------------------------------------------------------- output

log() {
  local level="$1"
  shift
  local line="[$level] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG_FILE"
}

die() {
  log FATAL "$*"
  log FATAL "Log: $LOG_FILE"
  exit 1
}

# Escape a string for safe embedding in an AppleScript double-quoted literal.
applescript_quote() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Run a command as root through the macOS authentication dialog.
run_admin() {
  local script
  script="$(applescript_quote "$1")"
  /usr/bin/osascript -e "do shell script \"$script\" with administrator privileges"
}

# ----------------------------------------------------------------- single run

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    trap 'rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT INT TERM
    return 0
  fi
  local existing=""
  [ -f "$LOCK_DIR/pid" ] && existing="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$existing" ] && kill -0 "$existing" 2>/dev/null; then
    log INFO "Another $APP_NAME run is already active (PID $existing)."
    return 1
  fi
  log WARN "Clearing a stale lock from a previous run."
  rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true
  mkdir "$LOCK_DIR" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$LOCK_DIR/pid"
  trap 'rm -rf "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT INT TERM
  return 0
}

# --------------------------------------------------------------- zoom lookup

find_zoom_app() {
  local candidate
  for candidate in \
    "/Applications/zoom.us.app" \
    "$HOME/Applications/zoom.us.app" \
    "/Applications/Zoom.app" \
    "$HOME/Applications/Zoom.app"
  do
    if [ -d "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  local found
  found="$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$ZOOM_BUNDLE_ID'" 2>/dev/null | head -n 1)"
  if [ -n "$found" ] && [ -d "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

# Helpers keep the old session in memory and rewrite the profile after a
# partial quit. CptHost / ZoomOpener are why a folder wipe still opened as
# the previous name and still offered "Join new room?".
ZOOM_HELPER_PATTERNS='zoom.us|ZoomOpener|ZoomAutoUpdater|CptHost|aomhost|caphost|airhost|zCrashReport|TranscodeServer|CptShare'

zoom_running() {
  /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -i -f "$ZOOM_HELPER_PATTERNS" >/dev/null 2>&1 && return 0
  return 1
}

stop_zoom() {
  # Do not ask Zoom to quit. If a meeting is open it shows "Leave meeting?"
  # and AppleScript waits forever — that is the freeze where nothing closes.
  log ACTION "Force-closing Zoom now (no prompt)"
  /usr/bin/killall -9 zoom.us ZoomOpener ZoomAutoUpdater CptHost aomhost caphost airhost zCrashReport TranscodeServer CptShare >/dev/null 2>&1 || true
  /usr/bin/pkill -9 -x "zoom.us" >/dev/null 2>&1 || true
  /usr/bin/pkill -9 -f "/zoom.us.app/" >/dev/null 2>&1 || true
  sleep 1
  if zoom_running; then
    /usr/bin/pkill -9 -i -f "$ZOOM_HELPER_PATTERNS" >/dev/null 2>&1 || true
    sleep 1
  fi
  if zoom_running; then
    log WARN "A Zoom process is still running. Force Quit it with Cmd+Option+Esc."
  else
    log OK "Zoom closed."
  fi
}

# ------------------------------------------------------- level 1: local reset

# Skip 1132.WTF's own folders so a glob on *zoom* cannot eat our backups.
is_our_path() {
  case "$1" in
    *"/1132.WTF"*|*"/wtf.fix1132"*) return 0 ;;
    *) return 1 ;;
  esac
}

label_from_path() {
  local rel="${1#"$HOME"/}"
  printf '%s' "$rel" | tr '/ :' '___' | tr -cd 'A-Za-z0-9._-' | cut -c1-96
}

# label|path pairs. Labels keep backup folder names unique and let restore put
# each item back exactly where it came from. The first block is every path
# Zoom is known to use for the display name, meeting history ("Join new
# room?"), SSO, and device id. The glob block catches folders Zoom adds in
# later builds (Group Containers, extra preference domains, ~/.zoomus).
identity_targets() {
  {
    printf '%s\n' "app_support|$HOME/Library/Application Support/zoom.us"
    printf '%s\n' "app_support_zoom|$HOME/Library/Application Support/Zoom"
    printf '%s\n' "app_support_xos|$HOME/Library/Application Support/$ZOOM_BUNDLE_ID"
    printf '%s\n' "app_support_chat|$HOME/Library/Application Support/ZoomChat"
    printf '%s\n' "app_support_updater|$HOME/Library/Application Support/ZoomAutoUpdater"
    printf '%s\n' "preferences|$HOME/Library/Preferences/$ZOOM_BUNDLE_ID.plist"
    printf '%s\n' "preferences_zoomus|$HOME/Library/Preferences/zoom.us.plist"
    printf '%s\n' "preferences_config|$HOME/Library/Preferences/us.zoom.config.plist"
    printf '%s\n' "preferences_chat|$HOME/Library/Preferences/ZoomChat.plist"
    printf '%s\n' "preferences_updater|$HOME/Library/Preferences/us.zoom.ZoomAutoUpdater.plist"
    printf '%s\n' "preferences_updater2|$HOME/Library/Preferences/us.zoom.updater.plist"
    printf '%s\n' "caches|$HOME/Library/Caches/$ZOOM_BUNDLE_ID"
    printf '%s\n' "caches_com|$HOME/Library/Caches/com.zoom.us"
    printf '%s\n' "caches_zoom|$HOME/Library/Caches/Zoom"
    printf '%s\n' "caches_updater|$HOME/Library/Caches/us.zoom.updater"
    printf '%s\n' "cookies|$HOME/Library/Cookies/$ZOOM_BUNDLE_ID.binarycookies"
    printf '%s\n' "saved_state|$HOME/Library/Saved Application State/$ZOOM_BUNDLE_ID.savedState"
    printf '%s\n' "http_storage|$HOME/Library/HTTPStorages/$ZOOM_BUNDLE_ID"
    printf '%s\n' "http_storage_cookies|$HOME/Library/HTTPStorages/$ZOOM_BUNDLE_ID.binarycookies"
    printf '%s\n' "logs|$HOME/Library/Logs/zoom.us"
    printf '%s\n' "logs_zoom|$HOME/Library/Logs/Zoom"
    printf '%s\n' "webkit|$HOME/Library/WebKit/$ZOOM_BUNDLE_ID"
    printf '%s\n' "webkit_com|$HOME/Library/WebKit/com.zoom.us"
    printf '%s\n' "containers|$HOME/Library/Containers/$ZOOM_BUNDLE_ID"
    printf '%s\n' "containers_com|$HOME/Library/Containers/com.zoom.us"
    printf '%s\n' "dot_zoomus|$HOME/.zoomus"

    # This brace is piped, so it runs in a subshell — do not use `local` here.
    # nullglob so an unused pattern does not emit itself as a fake path.
    shopt -s nullglob
    for p in \
      "$HOME/Library/Group Containers/"*[Zz]oom* \
      "$HOME/Library/Containers/"*[Zz]oom* \
      "$HOME/Library/Application Support/"*[Zz]oom* \
      "$HOME/Library/Caches/"*[Zz]oom* \
      "$HOME/Library/Logs/"*[Zz]oom* \
      "$HOME/Library/Preferences/"*[Zz]oom* \
      "$HOME/Library/WebKit/"*[Zz]oom* \
      "$HOME/Library/HTTPStorages/"*[Zz]oom* \
      "$HOME/Library/LaunchAgents/"*[Zz]oom* \
      "$HOME/Library/LaunchAgents/"*Zoom* \
      "$HOME/.zoomus"
    do
      is_our_path "$p" && continue
      printf '%s\n' "$(label_from_path "$p")|$p"
    done
    shopt -u nullglob
  } | awk -F'|' 'NF == 2 && $2 != "" && !seen[$2]++'
}

# Claim a backup directory that does not exist yet. Plain mkdir, not mkdir -p,
# so a name already in use is reported rather than silently shared: two runs in
# the same second must never write into one backup.
new_backup_dir() {
  local stamp attempt candidate
  stamp="$(date +%Y-%m-%d_%H%M%S)"
  for attempt in "" _2 _3 _4 _5 _6 _7 _8 _9; do
    candidate="$BACKUP_DIR/${stamp}${attempt}"
    if mkdir "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Move a path into the backup. LaunchAgents are unloaded first so ZoomOpener
# cannot rewrite the profile while we are moving it. Falls back to copy+rm
# when mv cannot cross volumes or a file is briefly busy.
move_identity() {
  local path="$1" dest="$2"
  case "$path" in
    */LaunchAgents/*.plist)
      /bin/launchctl bootout "gui/$(id -u)" "$path" >/dev/null 2>&1 ||
        /bin/launchctl unload "$path" >/dev/null 2>&1 || true
      ;;
  esac
  mkdir -p "$(dirname "$dest")"
  if mv "$path" "$dest" 2>/dev/null; then
    return 0
  fi
  if cp -R "$path" "$dest" 2>/dev/null; then
    rm -rf "$path" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# Zoom caches plist values in cfprefsd. Deleting the file is not enough —
# cfprefsd writes the old name and rooms straight back on the next launch.
flush_zoom_defaults() {
  local domain
  for domain in \
    "$ZOOM_BUNDLE_ID" \
    zoom.us \
    us.zoom.config \
    us.zoom.updater \
    us.zoom.ZoomAutoUpdater \
    ZoomChat \
    us.zoom.pkginstall
  do
    if /usr/bin/defaults read "$domain" >/dev/null 2>&1; then
      if /usr/bin/defaults delete "$domain" >/dev/null 2>&1; then
        log OK "Cleared cached defaults for $domain"
      else
        log WARN "Could not clear cached defaults for $domain"
      fi
    fi
  done
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
}

# One security delete-generic-password call removes ONE item. Zoom stores
# many (SSO, "keep me signed in", meeting history). A leftover item is what
# signed the user back in as the previous name after every reset.
scrub_zoom_keychain() {
  local item n total=0
  for item in \
    "Zoom Safe Meeting Storage" \
    "zoom.us" \
    "Zoom" \
    "us.zoom.xos" \
    "Zoom SSO" \
    "ZoomChat" \
    "ZoomAutoUpdater" \
    "us.zoom.updater"
  do
    n=0
    while [ "$n" -lt 40 ]; do
      /usr/bin/security delete-generic-password -l "$item" >/dev/null 2>&1 || break
      n=$((n + 1))
    done
    while [ "$n" -lt 40 ]; do
      /usr/bin/security delete-generic-password -s "$item" >/dev/null 2>&1 || break
      n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
      log OK "Removed $n keychain item(s) for $item"
      total=$((total + n))
    fi
  done
  for item in zoom.us www.zoom.us api.zoom.us "*.zoom.us"; do
    n=0
    while [ "$n" -lt 20 ]; do
      /usr/bin/security delete-internet-password -s "$item" >/dev/null 2>&1 || break
      n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
      log OK "Removed $n internet-password item(s) for $item"
      total=$((total + n))
    fi
  done
  if [ "$total" -eq 0 ]; then
    log INFO "No Zoom keychain items were present."
  fi
}

urlencode() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
  else
    printf '%s' "$1" | sed 's/ /%20/g'
  fi
}

# New Zoom display name every launch. Hosts often block a name they have
# already seen, so Guest / the Mac login / a reused name is a hole.
random_display_name() {
  local firsts=(Alex Sam Jordan Casey Riley Quinn Avery Morgan Taylor Jamie Drew Reese Kai Rowan Sky Finn)
  local lasts=(Chen Patel Garcia Kim Novak Silva Haddad Okafor Ivanov Dubois Rossi Nakamura Andersson Costa Weber)
  local first last num
  first="${firsts[RANDOM % ${#firsts[@]}]}"
  last="${lasts[RANDOM % ${#lasts[@]}]}"
  num="$(printf '%03d' $((RANDOM % 1000)))"
  printf '%s %s %s' "$first" "$last" "$num"
}

resolve_display_name() {
  local given="${1:-}"
  local me me_lc given_lc
  me="$(id -un 2>/dev/null || true)"
  given="$(printf '%s' "$given" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  me_lc="$(printf '%s' "$me" | tr '[:upper:]' '[:lower:]')"
  given_lc="$(printf '%s' "$given" | tr '[:upper:]' '[:lower:]')"
  if [ -z "$given" ] || [ "$given_lc" = "guest" ] || [ "$given_lc" = "user" ] || \
     { [ -n "$me_lc" ] && [ "$given_lc" = "$me_lc" ]; }; then
    random_display_name
    return
  fi
  printf '%s' "$given"
}

# Build a zoommtg join URL from WTF1132_MEETING / WTF1132_JOIN_URL and an
# optional WTF1132_DISPLAY_NAME. Passing uname= stops Zoom prefilling the
# Mac account name (the reason a clean profile still said "dustin").
build_join_url() {
  local raw="${WTF1132_JOIN_URL:-${WTF1132_MEETING:-${WTF1132_MEETING_ID:-}}}"
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  local name="${WTF1132_DISPLAY_NAME:-}"
  local encoded=""
  if [ -n "$name" ]; then
    encoded="$(urlencode "$name")"
  fi

  if [ -z "$raw" ]; then
    return 1
  fi

  case "$raw" in
    zoommtg://*)
      if [ -n "$encoded" ] && ! printf '%s' "$raw" | grep -q 'uname='; then
        printf '%s&uname=%s' "$raw" "$encoded"
      else
        printf '%s' "$raw"
      fi
      return 0
      ;;
  esac

  local id pwd
  id="$(printf '%s' "$raw" | sed -n 's|.*/j/\([0-9][0-9]*\).*|\1|p')"
  if [ -z "$id" ]; then
    id="$(printf '%s' "$raw" | sed -n 's/.*confno=\([0-9][0-9]*\).*/\1/p')"
  fi
  if [ -z "$id" ]; then
    id="$(printf '%s' "$raw" | tr -cd '0-9')"
  fi
  pwd="$(printf '%s' "$raw" | sed -n 's/.*[?&]pwd=\([^&]*\).*/\1/p')"
  [ -z "$id" ] && return 1

  local url="zoommtg://zoom.us/join?confno=${id}"
  [ -n "$pwd" ] && url="${url}&pwd=${pwd}"
  [ -n "$encoded" ] && url="${url}&uname=${encoded}"
  printf '%s' "$url"
}

do_wipe_identity() {
  local backup moved manifest
  backup="$(new_backup_dir)" ||
    die "Could not create a backup directory under $BACKUP_DIR"
  manifest="$backup/manifest.txt"
  : >"$manifest"
  moved=0

  while IFS='|' read -r label path; do
    [ -z "${label:-}" ] && continue
    [ -e "$path" ] || continue
    if move_identity "$path" "$backup/$label"; then
      printf '%s|%s\n' "$label" "$path" >>"$manifest"
      log OK "Reset $path"
      moved=$((moved + 1))
    else
      log WARN "Could not reset $path"
    fi
  done < <(identity_targets)

  flush_zoom_defaults
  scrub_zoom_keychain
  rm -rf "$CLEAN_PROFILE_DIR"

  if [ "$moved" -eq 0 ]; then
    rm -f "$manifest"
    rmdir "$backup" 2>/dev/null || true
    log INFO "Zoom identity was already clean, nothing to back up."
  else
    log INFO "Backup written to $backup"
  fi
}

do_fix() {
  local zoom
  zoom="$(find_zoom_app || true)"
  [ -n "$zoom" ] || die "Zoom is not installed. Install Zoom from zoom.us, then run this again."
  log OK "Zoom: $zoom"

  stop_zoom
  do_wipe_identity

  if [ "${NO_LAUNCH:-${WTF1132_NO_LAUNCH:-0}}" = "1" ]; then
    return 0
  fi
  do_fresh_session "$zoom"
}

list_backups() {
  # Backup names are timestamps, so a reverse sort puts the newest first.
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -r
}

do_restore() {
  local latest
  latest="$(list_backups | head -n 1)"
  if [ -z "$latest" ]; then
    log WARN "There is no backup to restore."
    return 1
  fi
  local backup="$BACKUP_DIR/$latest"
  log INFO "Restoring backup $latest"
  stop_zoom

  if [ ! -f "$backup/manifest.txt" ]; then
    log WARN "Backup has no manifest, so its items cannot be placed automatically."
    return 1
  fi

  while IFS='|' read -r label path; do
    [ -z "${label:-}" ] && continue
    [ -e "$backup/$label" ] || continue
    rm -rf "$path" 2>/dev/null || true
    mkdir -p "$(dirname "$path")"
    if cp -R "$backup/$label" "$path" 2>/dev/null; then
      log OK "Restored $path"
    else
      log WARN "Could not restore $path"
    fi
  done <"$backup/manifest.txt"

  rm -rf "$CLEAN_PROFILE_DIR"

  log DONE "Restore finished."
  return 0
}

# ---------------------------------------------------- level 2: user rotation

random_password() {
  # Readable classes only, because the user has to type this at the macOS
  # login window to use the throwaway account.
  LC_ALL=C tr -dc 'A-Za-z2-9' </dev/urandom | head -c 16
}

next_slot() {
  local raw=1
  if [ -f "$SLOT_FILE" ]; then
    raw="$(tr -d '[:space:]' <"$SLOT_FILE" 2>/dev/null || printf '1')"
  fi
  case "$raw" in
    1 | 2 | 3) printf '%s' "$raw" ;;
    *) printf '1' ;;
  esac
}

slot_to_remove() {
  case "$1" in
    1) printf '2' ;;
    2) printf '3' ;;
    3) printf '1' ;;
  esac
}

mac_user_exists() {
  /usr/bin/dscl . -read "/Users/$1" >/dev/null 2>&1
}

# Hidden throwaway user on THIS desktop. Zoom's process runs as that user
# (launchctl asuser + sudo -u). osascript is only used for the password
# prompt. When Zoom quits, the watcher deletes the user.
do_fresh_session() {
  local zoom="${1:-}"
  if [ -z "$zoom" ]; then
    zoom="$(find_zoom_app || true)"
  fi
  [ -n "$zoom" ] || die "Zoom is not installed on this Mac. Install Zoom from zoom.us, then run this again."

  local helper
  helper="$(cd "$(dirname "$0")" && pwd)/1132wtf-session.sh"
  [ -f "$helper" ] || die "Missing session helper: $helper"
  chmod +x "$helper" 2>/dev/null || true

  local session_dir="$SUPPORT_DIR/session"
  rm -rf "$session_dir"
  mkdir -p "$session_dir"
  : >"$LOG_DIR/session.log"
  local name
  name="$(resolve_display_name "${WTF1132_DISPLAY_NAME:-}")"
  WTF1132_DISPLAY_NAME="$name"
  export WTF1132_DISPLAY_NAME
  printf '%s\n' "$name" >"$LOG_DIR/last_display_name.txt"
  local join_url=""
  join_url="$(build_join_url || true)"
  local meeting
  meeting="$(printf '%s' "${WTF1132_MEETING:-${WTF1132_JOIN_URL:-}}" | tr -d '[:space:]')"
  if [ -n "$meeting" ]; then
    printf '%s' "$meeting" | /usr/bin/pbcopy >/dev/null 2>&1 || true
    printf '%s\n' "$meeting" >"$LOG_DIR/last_meeting.txt"
    log INFO "Meeting number is on the clipboard. Paste it into Zoom Join."
  fi
  printf '%s\n' "$zoom" >"$session_dir/zoom.path"
  printf '%s\n' "$join_url" >"$session_dir/join.url"
  printf '%s\n' "$name" >"$session_dir/display.name"
  printf '%s\n' "$LOG_DIR/session.log" >"$session_dir/session.log"

  log ACTION "macOS will ask for your password once. That creates a hidden temporary user."
  log INFO "This Zoom name is '$name' (new random name every launch)."
  log INFO "Zoom then starts as that user (launchctl asuser + sudo -u), not as $(id -un)."

  if ! run_admin "/bin/bash '$helper' --start-from '$session_dir'" >>"$LOG_FILE" 2>&1; then
    die "Need your Mac password to create the temporary Zoom profile."
  fi

  local waited=0
  while [ "$waited" -lt 25 ]; do
    if grep -q 'FATAL:' "$LOG_DIR/session.log" 2>/dev/null; then
      die "Could not start the temporary Zoom user. See $LOG_DIR/session.log"
    fi
    if grep -q "Zoom is running as" "$LOG_DIR/session.log" 2>/dev/null; then
      log OK "Zoom is running as '$name', not as $(id -un)."
      log DONE "Click Join. When you quit Zoom, the temporary user is deleted."
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if grep -q 'FATAL:' "$LOG_DIR/session.log" 2>/dev/null; then
    die "Could not start the temporary Zoom user. See $LOG_DIR/session.log"
  fi
  log OK "Temporary user is starting Zoom as '$name'."
  log DONE "Click Join. When you quit Zoom, the temporary user is deleted."
}

do_deep_fix() {
  do_fix
}

# The "browser" verb used to open a web page. That is disabled.
# It now does the same thing as STEP 1: wipe identity, open Zoom.app.
do_browser() {
  log INFO "This app does not open a web page. Opening Zoom.app."
  do_fix
}

# ------------------------------------------------------------------ autostart

autostart_on() {
  local app_root exe
  app_root="${APP_ROOT:-}"
  if [ -z "$app_root" ]; then
    die "autostart-on must be run from inside the app bundle."
  fi
  exe="$app_root/Contents/MacOS/$APP_NAME"

  mkdir -p "$HOME/Library/LaunchAgents"
  cat >"$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$BUNDLE_ID</string>
	<key>ProgramArguments</key>
	<array>
		<string>$exe</string>
		<string>--background</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardOutPath</key>
	<string>$LOG_DIR/launchagent.out.log</string>
	<key>StandardErrorPath</key>
	<string>$LOG_DIR/launchagent.err.log</string>
</dict>
</plist>
PLIST

  /bin/launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 ||
    /bin/launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  if /bin/launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 ||
    /bin/launchctl load -w "$LAUNCH_AGENT" >/dev/null 2>&1; then
    log OK "Autostart installed: $LAUNCH_AGENT"
  else
    die "Could not register the login item. See $LOG_FILE"
  fi
}

autostart_off() {
  /bin/launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" >/dev/null 2>&1 ||
    /bin/launchctl unload "$LAUNCH_AGENT" >/dev/null 2>&1 || true
  rm -f "$LAUNCH_AGENT"
  log OK "Autostart removed."
}

autostart_installed() {
  [ -f "$LAUNCH_AGENT" ]
}

# --------------------------------------------------------------------- status

do_status() {
  log INFO "$APP_NAME v$APP_VERSION"
  log INFO "User=$(id -un)  Host=$(hostname -s)  macOS=$(/usr/bin/sw_vers -productVersion 2>/dev/null || printf 'unknown')"
  log INFO "Arch=$(uname -m)"

  local zoom
  zoom="$(find_zoom_app || true)"
  if [ -n "$zoom" ]; then
    log OK "Zoom found: $zoom"
  else
    log WARN "Zoom was not found. Level 1 and 2 need the Zoom client installed."
  fi

  if zoom_running; then
    log INFO "Zoom running: yes"
  else
    log INFO "Zoom running: no"
  fi

  log INFO "Next deep-fix slot: $(next_slot)"

  local present=""
  local name
  for name in "${SLOT_NAMES[@]}"; do
    if mac_user_exists "$name"; then
      present="${present:+$present, }$name"
    fi
  done
  log INFO "Throwaway accounts present: ${present:-none}"

  local count
  count="$(list_backups | wc -l | tr -d ' ')"
  log INFO "Identity backups: $count"

  if autostart_installed; then
    log INFO "Autostart installed: yes"
  else
    log INFO "Autostart installed: no"
  fi

  [ -f "$LAST_RUN_FILE" ] && log INFO "Last run: $(cat "$LAST_RUN_FILE")"

  local leftovers=0
  while IFS='|' read -r label path; do
    [ -z "${label:-}" ] && continue
    [ -e "$path" ] || continue
    leftovers=$((leftovers + 1))
  done < <(identity_targets)
  log INFO "Zoom identity leftovers on disk: $leftovers"
  log INFO "Logs: $LOG_DIR"
}

# ----------------------------------------------------------------------- main

VERB="${1:-fix}"
[ $# -gt 0 ] && shift

log START "$APP_NAME verb=$VERB"

EXIT_CODE=0
case "$VERB" in
  status) do_status ;;
  browser)
    acquire_lock || die "Another $APP_NAME run is already active. Wait, or delete ~/Library/Application Support/$APP_NAME/run.lock"
    do_browser
    ;;
  logs)
    log INFO "$LOG_DIR"
    /usr/bin/open "$LOG_DIR" >/dev/null 2>&1 || true
    ;;
  autostart-on) autostart_on ;;
  autostart-off) autostart_off ;;
  fix)
    acquire_lock || die "Another $APP_NAME run is already active. Wait, or delete ~/Library/Application Support/$APP_NAME/run.lock"
    do_fix
    ;;
  deep-fix)
    acquire_lock || die "Another $APP_NAME run is already active. Wait, or delete ~/Library/Application Support/$APP_NAME/run.lock"
    do_deep_fix
    ;;
  restore)
    acquire_lock || exit 0
    do_restore || EXIT_CODE=1
    ;;
  *)
    die "Unknown verb '$VERB'. Try: status, fix, deep-fix, browser, restore, autostart-on, autostart-off, logs"
    ;;
esac

printf '%s verb=%s exit=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$VERB" "$EXIT_CODE" >"$LAST_RUN_FILE"
exit "$EXIT_CODE"
