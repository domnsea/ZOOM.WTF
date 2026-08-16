#!/usr/bin/env bash
#
# Build 1132.WTF for iOS. Must be run on a Mac with Xcode installed, because
# only Apple's toolchain can compile for iOS.
#
#   ./build-ios.sh                build for the simulator and check it compiles
#   ./build-ios.sh --simulator    build and install into a booted simulator
#   ./build-ios.sh --device       archive for a real iPhone (needs a signing team)
#
# For a real device you need a free or paid Apple developer account. Pass your
# team id:
#
#   TEAM_ID=ABCDE12345 ./build-ios.sh --device

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1

PROJECT="1132WTF.xcodeproj"
SCHEME="1132WTF"
MODE="check"

case "${1:-}" in
  --simulator) MODE="simulator" ;;
  --device) MODE="device" ;;
  "" | --check) MODE="check" ;;
  -h | --help)
    printf '%s\n' "Usage: $0 [--check | --simulator | --device]"
    exit 0
    ;;
  *)
    printf '%s\n' "Unknown option: $1" >&2
    exit 2
    ;;
esac

printf '=== Building 1132.WTF for iOS (%s) ===\n\n' "$MODE"

if [ "$(uname -s)" != "Darwin" ]; then
  cat <<'MESSAGE' >&2
This has to run on a Mac.

iOS apps can only be compiled by Apple's toolchain, which only exists on macOS.
There is no way around that from Linux or Windows, and any tool that claims
otherwise is either running a Mac for you remotely or not really building an
iOS app.

On a Mac:
  1. Install Xcode from the App Store
  2. Open 1132WTF.xcodeproj
  3. Pick a simulator and press Run

Everything in this package is a complete, ready-to-open Xcode project.
MESSAGE
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  printf '%s\n' "xcodebuild was not found. Install Xcode, then run:" >&2
  printf '%s\n' "  sudo xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

xcodebuild -version | head -2
printf '\n'

case "$MODE" in
  check)
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -quiet \
      CODE_SIGNING_ALLOWED=NO \
      build || exit 1
    printf '\nCompiles cleanly.\n'
    ;;

  simulator)
    DEVICE="${SIMULATOR:-iPhone 15}"
    printf 'Simulator: %s\n\n' "$DEVICE"

    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "platform=iOS Simulator,name=$DEVICE" \
      -derivedDataPath build \
      -quiet \
      CODE_SIGNING_ALLOWED=NO \
      build || exit 1

    APP="build/Build/Products/Debug-iphonesimulator/1132.WTF.app"
    if [ ! -d "$APP" ]; then
      printf '%s\n' "Build succeeded but $APP is missing." >&2
      exit 1
    fi

    open -a Simulator || true
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl install booted "$APP" || exit 1
    xcrun simctl launch booted wtf.fix1132.ios || exit 1
    printf '\nInstalled and launched in the simulator.\n'
    ;;

  device)
    if [ -z "${TEAM_ID:-}" ]; then
      cat <<'MESSAGE' >&2
A device build has to be signed, so TEAM_ID is required.

Find your team id in Xcode under Settings, Accounts, then Manage Certificates,
or at developer.apple.com under Membership. Then:

  TEAM_ID=ABCDE12345 ./build-ios.sh --device

A free Apple account works. The app will run for seven days before it needs
resigning, which is Apple's limit on free accounts, not a limit of this app.
MESSAGE
      exit 1
    fi

    printf 'Team: %s\n\n' "$TEAM_ID"
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -archivePath "build/1132WTF.xcarchive" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      -quiet \
      archive || exit 1

    printf '\nArchive: build/1132WTF.xcarchive\n'
    printf 'Open it in Xcode (Window, Organizer) to install on your iPhone,\n'
    printf 'or export an .ipa from there.\n'
    ;;
esac
