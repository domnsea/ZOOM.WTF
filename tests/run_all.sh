#!/usr/bin/env bash
#
# Run every 1132.WTF test suite.
#
# All of them work on Linux with no Mac, no phone, and no emulator. Suites whose
# toolchain is missing are reported as skipped rather than silently passing.
#
# Usage: tests/run_all.sh

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

RESULTS=()
FAILURES=0

run_suite() {
  # run_suite <label> <script> [required-command]
  local label="$1" script="$2" requirement="${3:-}"

  printf '\n========================================\n'
  printf '%s\n' "$label"
  printf '========================================\n'

  if [ -n "$requirement" ] && ! command -v "$requirement" >/dev/null 2>&1; then
    printf 'skipped: %s is not installed\n' "$requirement"
    RESULTS+=("SKIP  $label (no $requirement)")
    return 0
  fi

  if bash "$script"; then
    RESULTS+=("PASS  $label")
  else
    RESULTS+=("FAIL  $label")
    FAILURES=$((FAILURES + 1))
  fi
}

# Let the iOS suite find a Swift toolchain unpacked into the home directory.
if [ -x "$HOME/swift/usr/bin/swiftc" ]; then
  export PATH="$HOME/swift/usr/bin:$PATH"
fi

run_suite "Linux engine, end to end" tests/test_linux_engine.sh
run_suite "Android logic" tests/test_android_logic.sh javac
run_suite "iOS logic and Swift syntax" tests/test_ios_logic.sh swiftc
run_suite "Package integrity" tests/test_packages.sh

printf '\n========================================\n'
printf 'Summary\n'
printf '========================================\n'
for line in "${RESULTS[@]}"; do
  printf '  %s\n' "$line"
done
printf '\n'

if [ "$FAILURES" -gt 0 ]; then
  printf '%s suite(s) failed.\n\n' "$FAILURES"
  exit 1
fi
printf 'All suites passed.\n\n'
