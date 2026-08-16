#!/usr/bin/env bash
#
# Compile and run the iOS app's Foundation-only logic, and syntax-check every
# other Swift file in the app.
#
# The full app can only be built on a Mac, because SwiftUI, UIKit, and WebKit
# are Apple frameworks. MeetingLink and Identity import only Foundation, so they
# run anywhere the open-source Swift toolchain does, and the remaining files can
# still be parsed for syntax errors.
#
# Usage: tests/test_ios_logic.sh
#
# Set SWIFT to point at a specific toolchain if swiftc is not on PATH.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/platforms/ios/1132WTF"
# Named main.swift because Swift only permits top-level code in that filename.
TEST_FILE="$REPO_ROOT/tests/ios/main.swift"

SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
  if command -v swiftc >/dev/null 2>&1; then
    SWIFTC="$(command -v swiftc)"
  elif [ -x "$HOME/swift/usr/bin/swiftc" ]; then
    SWIFTC="$HOME/swift/usr/bin/swiftc"
  else
    printf '%s\n' "swiftc was not found. Install a Swift toolchain, or set SWIFTC." >&2
    printf '%s\n' "On a Mac, Xcode provides it. On Linux, see swift.org/download." >&2
    exit 1
  fi
fi

printf 'toolchain: %s\n' "$("$SWIFTC" --version 2>&1 | head -1)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- logic tests

printf '\ncompiling Foundation-only sources\n'
"$SWIFTC" -o "$WORK/logictests" \
  "$APP_DIR/MeetingLink.swift" \
  "$APP_DIR/Identity.swift" \
  "$TEST_FILE" || {
  printf '%s\n' "Compilation failed." >&2
  exit 1
}

"$WORK/logictests" || exit 1

# ------------------------------------------------------------- syntax checks

# The rest of the app imports SwiftUI, UIKit, and WebKit, which do not exist off
# Apple platforms, so they cannot be type-checked here. Parsing still catches
# every syntax error, which is what would stop the project opening in Xcode.
printf 'syntax check of the Apple-framework sources\n'
SYNTAX_FAILED=0
for source in "$APP_DIR"/*.swift; do
  name="$(basename "$source")"
  case "$name" in
    MeetingLink.swift | Identity.swift) continue ;;
  esac
  if "$SWIFTC" -parse "$source" >"$WORK/parse.log" 2>&1; then
    printf '  ok    %s parses\n' "$name"
  else
    # Missing Apple modules are expected off-platform and are not syntax errors.
    if grep -qE "no such module|cannot load underlying module" "$WORK/parse.log"; then
      printf '  ok    %s parses (Apple modules unavailable here, as expected)\n' "$name"
    else
      printf '  FAIL  %s\n' "$name"
      sed 's/^/        /' "$WORK/parse.log" | head -20
      SYNTAX_FAILED=1
    fi
  fi
done

printf '\n----------------------------------------\n'
if [ "$SYNTAX_FAILED" -ne 0 ]; then
  printf 'RESULT: FAILED\n\n'
  exit 1
fi
printf 'RESULT: PASSED\n\n'
