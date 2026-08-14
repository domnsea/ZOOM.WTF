#!/bin/bash
#
# 1132.WTF engine for macOS
# Implements the levels described in docs/ENGINE.md.
#
# Usage: 1132wtf-engine.sh <verb> [argument]
#   status | fix | deep-fix | browser [url] | restore
#   autostart-on | autostart-off | logs
#
# Shell based on purpose: it is architecture neutral, so one copy runs on both
# Intel and Apple Silicon with no build step and no notarised binary.

set -u
set -o pipefail

APP_NAME="1132.WTF"
APP_VERSION="1.0.0"
BUNDLE_ID="wtf.fix1132.mac"

SUPPORT_DIR="$HOME/Library/Application Support/$APP_NAME"
LOG_DIR="$HOME/Library/Logs/$APP_NAME"
BACKUP_DIR="$SUPPORT_DIR/backups"
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
LOG_FILE="$LOG_DIR/engine_$(date +%Y-%m-%d_%H%M%S).log"

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

zoom_running() {
  /usr/bin/pgrep -ix "zoom.us" >/dev/null 2>&1 && return 0
  /usr/bin/pgrep -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 && return 0
  return 1
}

stop_zoom() {
  if ! zoom_running; then
    log INFO "Zoom was not running."
    return 0
  fi
  log ACTION "Quitting Zoom"
  /usr/bin/osascript -e 'tell application "zoom.us" to quit' >/dev/null 2>&1 || true

  local waited=0
  while zoom_running && [ "$waited" -lt 10 ]; do
    sleep 1
    waited=$((waited + 1))
  done

  if zoom_running; then
    log WARN "Zoom ignored the quit request, forcing it."
    /usr/bin/pkill -ix "zoom.us" >/dev/null 2>&1 || true
    /usr/bin/pkill -f "zoom.us.app/Contents/MacOS" >/dev/null 2>&1 || true
    sleep 1
  fi

  if zoom_running; then
    log WARN "Zoom is still running. The reset may be incomplete."
  else
    log OK "Zoom stopped."
  fi
}

# ------------------------------------------------------- level 1: local reset

# label|path pairs. Labels keep backup folder names unique and let restore put
# each item back exactly where it came from.
identity_targets() {
  cat <<TARGETS
app_support|$HOME/Library/Application Support/zoom.us
preferences|$HOME/Library/Preferences/$ZOOM_BUNDLE_ID.plist
caches|$HOME/Library/Caches/$ZOOM_BUNDLE_ID
cookies|$HOME/Library/Cookies/$ZOOM_BUNDLE_ID.binarycookies
saved_state|$HOME/Library/Saved Application State/$ZOOM_BUNDLE_ID.savedState
http_storage|$HOME/Library/HTTPStorages/$ZOOM_BUNDLE_ID
TARGETS
}

do_fix() {
  local zoom
  zoom="$(find_zoom_app || true)"
  if [ -z "$zoom" ]; then
    die "Zoom is not installed on this Mac. Install Zoom, or use the browser bypass."
  fi
  log OK "Zoom: $zoom"

  stop_zoom

  local stamp backup moved manifest
  stamp="$(date +%Y-%m-%d_%H%M%S)"
  backup="$BACKUP_DIR/$stamp"
  mkdir -p "$backup"
  manifest="$backup/manifest.txt"
  : >"$manifest"
  moved=0

  while IFS='|' read -r label path; do
    [ -z "${label:-}" ] && continue
    [ -e "$path" ] || continue
    if mv "$path" "$backup/$label" 2>/dev/null; then
      printf '%s|%s\n' "$label" "$path" >>"$manifest"
      log OK "Reset $path"
      moved=$((moved + 1))
    else
      log WARN "Could not reset $path"
    fi
  done < <(identity_targets)

  # Zoom's cached preference values live in cfprefsd too, so drop them there.
  if /usr/bin/defaults read "$ZOOM_BUNDLE_ID" >/dev/null 2>&1; then
    if /usr/bin/defaults delete "$ZOOM_BUNDLE_ID" >/dev/null 2>&1; then
      log OK "Cleared cached defaults for $ZOOM_BUNDLE_ID"
    else
      log WARN "Could not clear cached defaults for $ZOOM_BUNDLE_ID"
    fi
  fi

  # Keychain items cannot be exported without prompting for each one, so these
  # are deleted rather than backed up. Zoom recreates them on next sign in.
  local item
  for item in "Zoom Safe Meeting Storage" "zoom.us" "Zoom"; do
    if /usr/bin/security delete-generic-password -l "$item" >/dev/null 2>&1; then
      log OK "Removed keychain item: $item"
    fi
  done

  if [ "$moved" -eq 0 ]; then
    rmdir "$backup" 2>/dev/null || true
    log INFO "Zoom identity was already clean, nothing to back up."
  else
    log INFO "Backup written to $backup"
  fi

  if [ "${NO_LAUNCH:-0}" != "1" ]; then
    log ACTION "Opening Zoom with a fresh identity"
    if /usr/bin/open -a "$zoom"; then
      log OK "Zoom started."
    else
      log WARN "Could not open Zoom automatically. Open it from Applications."
    fi
  fi

  log DONE "Level 1 reset complete. Rejoin the meeting now."
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

do_deep_fix() {
  local slot remove_slot active remove password
  slot="$(next_slot)"
  remove_slot="$(slot_to_remove "$slot")"
  active="${SLOT_NAMES[$((slot - 1))]}"
  remove="${SLOT_NAMES[$((remove_slot - 1))]}"

  case "$active" in
    "$SLOT_PREFIX"*) : ;;
    *) die "Refusing to act on '$active': not a $APP_NAME rotation account." ;;
  esac

  log INFO "Rotation: preparing slot $slot ($active), destroying slot $remove_slot ($remove)"

  password="$(random_password)"
  [ -n "$password" ] || die "Could not generate a password."

  # One authentication prompt covers both the delete and the create.
  local script=""
  if mac_user_exists "$remove"; then
    script="/usr/sbin/sysadminctl -deleteUser $remove; "
  fi
  if mac_user_exists "$active"; then
    script="${script}/usr/bin/dscl . -passwd /Users/$active '$password'"
  else
    script="${script}/usr/sbin/sysadminctl -addUser $active -fullName '$APP_NAME Guest' -password '$password'"
  fi

  log ACTION "Asking for administrator rights to rotate the throwaway account"
  if ! run_admin "$script" >>"$LOG_FILE" 2>&1; then
    die "Administrator rights were refused, so the throwaway account was not created."
  fi

  if mac_user_exists "$active"; then
    log OK "Throwaway account ready: $active"
  else
    die "The throwaway account was not created. See $LOG_FILE"
  fi

  local following
  following=$((slot + 1))
  [ "$following" -gt 3 ] && following=1
  printf '%s\n' "$following" >"$SLOT_FILE"
  log STATE "Next deep-fix will use slot $following"

  # macOS will not run a GUI app as another user on this desktop, so the
  # remaining step is a genuine user switch. Show the credentials and offer it.
  log INFO "Account: $active"
  log INFO "Password: (shown in the dialog, not written to this log)"

  local message="A clean macOS account is ready.

    Account:   $active
    Password:  $password

Zoom sees this as a completely different machine-local identity.

Next: switch to that account, open Zoom, and join the meeting. Your own
account and files are untouched. Switch back at any time.

This account is deleted automatically the next time the rotation reaches it."

  local choice
  choice="$(/usr/bin/osascript \
    -e "display dialog \"$(applescript_quote "$message")\" \
        buttons {\"Later\", \"Switch now\"} default button \"Switch now\" \
        with title \"$APP_NAME\"" 2>/dev/null || true)"

  if printf '%s' "$choice" | grep -q "Switch now"; then
    local cgsession="/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    if [ -x "$cgsession" ]; then
      log ACTION "Opening the login window for the account switch"
      "$cgsession" -suspend >/dev/null 2>&1 || log WARN "Could not open the login window."
    else
      log WARN "Fast user switching helper not found. Switch from the Apple menu."
    fi
  fi

  log DONE "Level 2 rotation complete."
}

# ----------------------------------------------------- level 3: browser join

do_browser() {
  local url="${1:-https://zoom.us/join}"
  local opened=0

  # Chromium family and Firefox can be told to open a private window straight
  # from the command line. Safari cannot, so it is the last resort.
  if [ -d "/Applications/Google Chrome.app" ]; then
    log ACTION "Opening a private window in Google Chrome"
    /usr/bin/open -na "Google Chrome" --args --incognito "$url" && opened=1
  elif [ -d "/Applications/Microsoft Edge.app" ]; then
    log ACTION "Opening a private window in Microsoft Edge"
    /usr/bin/open -na "Microsoft Edge" --args --inprivate "$url" && opened=1
  elif [ -d "/Applications/Brave Browser.app" ]; then
    log ACTION "Opening a private window in Brave"
    /usr/bin/open -na "Brave Browser" --args --incognito "$url" && opened=1
  elif [ -d "/Applications/Firefox.app" ]; then
    log ACTION "Opening a private window in Firefox"
    /usr/bin/open -na "Firefox" --args -private-window "$url" && opened=1
  fi

  if [ "$opened" -ne 1 ]; then
    log WARN "No browser with a command-line private mode was found."
    log INFO "Opening your default browser. Use File > New Private Window yourself."
    /usr/bin/open "$url" || die "Could not open a browser."
  fi

  log OK "Join in that window, and choose \"Join from your browser\"."
  log DONE "Level 3 bypass ready."
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
  log INFO "Logs: $LOG_DIR"
}

# ----------------------------------------------------------------------- main

VERB="${1:-fix}"
[ $# -gt 0 ] && shift

log START "$APP_NAME verb=$VERB"

EXIT_CODE=0
case "$VERB" in
  status) do_status ;;
  browser) do_browser "${1:-}" ;;
  logs)
    log INFO "$LOG_DIR"
    /usr/bin/open "$LOG_DIR" >/dev/null 2>&1 || true
    ;;
  autostart-on) autostart_on ;;
  autostart-off) autostart_off ;;
  fix)
    acquire_lock || exit 0
    do_fix
    ;;
  deep-fix)
    acquire_lock || exit 0
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
