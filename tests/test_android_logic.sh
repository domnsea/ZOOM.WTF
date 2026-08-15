#!/usr/bin/env bash
#
# Compile and run the Android app's Android-free logic on a plain JDK.
#
# MeetingLink and Identity touch nothing from the Android framework, so they can
# be tested here without an emulator or the SDK. This covers the meeting link
# parsing, which is the part most likely to break quietly.
#
# Usage: tests/test_android_logic.sh

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/platforms/android/app/src/main/java"
TEST_DIR="$REPO_ROOT/tests/android"

if ! command -v javac >/dev/null 2>&1; then
  printf '%s\n' "javac was not found. Install a JDK to run these tests." >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

javac -d "$WORK" \
  "$SOURCE_DIR/wtf/fix1132/android/MeetingLink.java" \
  "$SOURCE_DIR/wtf/fix1132/android/Identity.java" \
  "$TEST_DIR/wtf/fix1132/android/LogicTest.java" || {
  printf '%s\n' "Compilation failed." >&2
  exit 1
}

java -cp "$WORK" wtf.fix1132.android.LogicTest
