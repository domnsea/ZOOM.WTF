#!/bin/bash
# Clear the "downloaded from the internet" flag macOS puts on this package,
# then ad-hoc sign the app so Gatekeeper will launch it.
#
# A paid Apple Developer ID is required to notarize. This is the path Apple
# documents for software that does not have one: remove the quarantine, or
# use Privacy & Security → Open Anyway. It does not disable Gatekeeper.

set -u

APP_NAME="1132.WTF"

allow_target() {
  local target="$1"
  [ -e "$target" ] || return 0

  # -c clears every extended attribute, which is what Archive Utility copies
  # onto extracted files. -d com.apple.quarantine is the specific flag; doing
  # both covers older and newer macOS.
  xattr -cr "$target" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true

  if [ -d "$target/Contents/MacOS" ]; then
    chmod +x "$target/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    chmod +x "$target/Contents/Resources/1132wtf-engine.sh" 2>/dev/null || true
    chmod +x "$target/Contents/Resources/1132wtf-session.sh" 2>/dev/null || true
    if command -v codesign >/dev/null 2>&1; then
      # Ad-hoc signature (the "-" identity). Not notarized, but combined with
      # a cleared quarantine it is enough for Gatekeeper to allow a local open.
      codesign --force --deep --sign - "$target" >/dev/null 2>&1 || true
    fi
  fi
}

allow_tree() {
  local root="$1"
  [ -d "$root" ] || return 0
  xattr -cr "$root" 2>/dev/null || true
  xattr -dr com.apple.quarantine "$root" 2>/dev/null || true
  chmod +x "$root"/*.command "$root/allow-macos.sh" 2>/dev/null || true
  if [ -d "$root/$APP_NAME.app" ]; then
    allow_target "$root/$APP_NAME.app"
  fi
}

# When this file is executed directly (double-clicked as a helper, or run
# from Terminal), allow whatever sits next to it, then /Applications.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  HERE="$(cd "$(dirname "$0")" && pwd)"
  printf '%s\n' "=== Allow $APP_NAME on this Mac ==="
  allow_tree "$HERE"
  allow_target "/Applications/$APP_NAME.app"

  printf '%s\n' "Cleared the download flag and signed the app locally."
  printf '%s\n' ""
  if [ -d "/Applications/$APP_NAME.app" ]; then
    printf '%s\n' "Opening /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app" && exit 0
  fi
  if [ -d "$HERE/$APP_NAME.app" ]; then
    printf '%s\n' "Opening $HERE/$APP_NAME.app"
    open "$HERE/$APP_NAME.app" && exit 0
  fi
  printf '%s\n' "Could not open the app automatically."
  printf '%s\n' "System Settings → Privacy & Security → Open Anyway"
  read -r -p "Press Return to close. " _
fi
