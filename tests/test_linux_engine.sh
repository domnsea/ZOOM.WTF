#!/usr/bin/env bash
#
# End-to-end tests for the Linux engine.
#
# Everything runs against a throwaway HOME and a stub Zoom binary, so the tests
# never touch a real Zoom install and never need root. Level 2 is not exercised
# here because creating operating-system users requires root.
#
# Usage: tests/test_linux_engine.sh

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$REPO_ROOT/platforms/linux/1132wtf"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '  ok    %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL  %s\n' "$1"
  [ -n "${2:-}" ] && printf '        %s\n' "$2"
}

check() {
  # check <description> <condition-as-command...>
  local description="$1"
  shift
  if "$@"; then
    pass "$description"
  else
    fail "$description" "condition failed: $*"
  fi
}

check_contains() {
  local description="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    pass "$description"
  else
    fail "$description" "expected to find: $needle"
  fi
}

# --------------------------------------------------------------------- harness

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

FAKE_HOME="$SANDBOX/home"
mkdir -p "$FAKE_HOME"

# A stub that stands in for the Zoom launcher. It must be executable and must
# exit immediately, because the engine only ever starts it in the background.
ZOOM_STUB="$SANDBOX/zoom-stub"
printf '#!/bin/sh\nexit 0\n' >"$ZOOM_STUB"
chmod +x "$ZOOM_STUB"

run_engine() {
  env -i \
    HOME="$FAKE_HOME" \
    PATH="/usr/bin:/bin" \
    NO_COLOR=1 \
    WTF1132_ZOOM_BIN="$ZOOM_STUB" \
    WTF1132_NO_LAUNCH=1 \
    WTF1132_ASSUME_YES=1 \
    bash "$ENGINE" "$@" 2>&1
}

state_dir() { printf '%s' "$FAKE_HOME/.local/share/1132wtf"; }

seed_identity() {
  mkdir -p "$FAKE_HOME/.zoom/data"
  printf 'device-id=SEEDED-1132\n' >"$FAKE_HOME/.zoom/data/zoomus.db"
  mkdir -p "$FAKE_HOME/.config"
  printf '[General]\nseeded=yes\n' >"$FAKE_HOME/.config/zoomus.conf"
  mkdir -p "$FAKE_HOME/.cache/zoom"
  printf 'cached\n' >"$FAKE_HOME/.cache/zoom/blob"
}

printf '\n1132.WTF Linux engine tests\n'
printf 'sandbox: %s\n\n' "$SANDBOX"

# ------------------------------------------------------------------ 1. basics

printf 'version and help\n'
out="$(run_engine version)"
check_contains "version prints the name and version" "$out" "1132.WTF 1.0.0"

out="$(run_engine help)"
check_contains "help lists the fix verb" "$out" "fix "
check_contains "help lists the deep-fix verb" "$out" "deep-fix"
check_contains "help lists the browser verb" "$out" "browser"

run_engine bogus-verb >/dev/null 2>&1
code=$?
check "unknown verb exits 2" test "$code" -eq 2

# ------------------------------------------------------------------ 2. status

printf '\nstatus on a clean machine\n'
out="$(run_engine status)"
check_contains "status finds the stub Zoom" "$out" "Zoom found:"
# detect_zoom runs in a command substitution, so the packaging kind has to be
# derived from the returned spec rather than set as a global.
check_contains "status reports the packaging kind, not 'none'" "$out" "(native)"
check_contains "status reports no identity data" "$out" "No Zoom identity data on disk"
check_contains "status reports slot 1 first" "$out" "Next deep-fix slot: 1"
check_contains "status reports no throwaway users" "$out" "Throwaway users present: none"
check_contains "status reports autostart off" "$out" "Autostart installed: no"

printf '\nstatus with identity data present\n'
seed_identity
out="$(run_engine status)"
check_contains "status sees ~/.zoom" "$out" "$FAKE_HOME/.zoom"
check_contains "status sees zoomus.conf" "$out" "$FAKE_HOME/.config/zoomus.conf"
check_contains "status sees the cache" "$out" "$FAKE_HOME/.cache/zoom"

# -------------------------------------------------------------- 3. level 1 fix

printf '\nlevel 1 fix\n'
out="$(run_engine fix)"
check_contains "fix reports completion" "$out" "Level 1 reset complete"
check "fix removed ~/.zoom" test ! -e "$FAKE_HOME/.zoom"
check "fix removed zoomus.conf" test ! -e "$FAKE_HOME/.config/zoomus.conf"
check "fix removed the cache" test ! -e "$FAKE_HOME/.cache/zoom"

backup_count=$(find "$(state_dir)/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
check "fix created exactly one backup" test "$backup_count" -eq 1

backup="$(find "$(state_dir)/backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
check "backup has a manifest" test -f "$backup/manifest.txt"
check "backup kept the seeded database" test -f "$backup/zoom_home/data/zoomus.db"
check_contains "manifest records the original path" "$(cat "$backup/manifest.txt")" \
  "zoom_home|$FAKE_HOME/.zoom"

seeded="$(cat "$backup/zoom_home/data/zoomus.db")"
check_contains "backed up file keeps its contents" "$seeded" "SEEDED-1132"

printf '\nfix on an already clean machine\n'
out="$(run_engine fix)"
check_contains "second fix reports nothing to back up" "$out" "already clean"
backup_count=$(find "$(state_dir)/backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
check "second fix did not leave an empty backup" test "$backup_count" -eq 1

# -------------------------------------------------------------- 4. restore

printf '\nrestore\n'
out="$(run_engine restore)"
check_contains "restore reports completion" "$out" "Restore finished"
check "restore put ~/.zoom back" test -d "$FAKE_HOME/.zoom"
check "restore put zoomus.conf back" test -f "$FAKE_HOME/.config/zoomus.conf"
check "restore put the cache back" test -d "$FAKE_HOME/.cache/zoom"
restored="$(cat "$FAKE_HOME/.zoom/data/zoomus.db" 2>/dev/null || printf 'MISSING')"
check_contains "restored file has the original contents" "$restored" "SEEDED-1132"

printf '\nrestore with no backups\n'
rm -rf "$(state_dir)/backups"
run_engine restore >/dev/null 2>&1
code=$?
check "restore with no backup exits 1" test "$code" -eq 1

# -------------------------------------------------------------- 5. autostart

printf '\nautostart\n'
autostart="$FAKE_HOME/.config/autostart/1132wtf.desktop"
out="$(run_engine autostart-on)"
check_contains "autostart-on reports success" "$out" "Autostart installed"
check "autostart desktop file exists" test -f "$autostart"
check_contains "desktop file runs the fix verb" "$(cat "$autostart")" "fix"
check_contains "desktop file declares its type" "$(cat "$autostart")" "Type=Application"
check_contains "desktop file references the icon" "$(cat "$autostart")" "Icon=1132wtf"

out="$(run_engine status)"
check_contains "status now reports autostart on" "$out" "Autostart installed: yes"

out="$(run_engine autostart-off)"
check_contains "autostart-off reports success" "$out" "Autostart removed"
check "autostart desktop file is gone" test ! -f "$autostart"

# ---------------------------------------------------- 6. missing zoom handling

printf '\nzoom not installed\n'
out="$(env -i HOME="$FAKE_HOME" PATH="/usr/bin:/bin" NO_COLOR=1 \
  WTF1132_NO_LAUNCH=1 WTF1132_ASSUME_YES=1 bash "$ENGINE" fix 2>&1)"
code=$?
check "fix without Zoom exits non-zero" test "$code" -ne 0
check_contains "fix without Zoom says so plainly" "$out" "Zoom is not installed"
check_contains "fix without Zoom points at the browser bypass" "$out" "browser"

# --------------------------------------------------------------- 7. locking

printf '\nsingle instance lock\n'
lock="$(state_dir)/run.lock"
mkdir -p "$lock"
printf '%s\n' "$$" >"$lock/pid"
out="$(run_engine fix)"
check_contains "a live lock stops a second run" "$out" "already active"
rm -rf "$lock"

mkdir -p "$lock"
printf '%s\n' "999999" >"$lock/pid"
out="$(run_engine fix)"
check_contains "a stale lock is cleared" "$out" "stale lock"
check "stale lock did not block the run" test -z "$(printf '%s' "$out" | grep -F 'already active' || true)"

# ------------------------------------------------------------------ 8. logging

printf '\nlogging\n'
log_count=$(find "$(state_dir)/logs" -name 'engine_*.log' 2>/dev/null | wc -l)
check "each run wrote a log file" test "$log_count" -gt 5
newest_log="$(find "$(state_dir)/logs" -name 'engine_*.log' -printf '%T@ %p\n' | sort -rn | head -n 1 | cut -d' ' -f2-)"
check_contains "log lines use the [LEVEL] format" "$(cat "$newest_log")" "[START]"
check "last run was recorded" test -f "$(state_dir)/lastrun.txt"

# -------------------------------------------------------------------- summary

printf '\n----------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAILED\n\n'
  exit 1
fi
printf 'RESULT: PASSED\n\n'
exit 0
