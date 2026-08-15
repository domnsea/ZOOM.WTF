#!/usr/bin/env bash
#
# Build the distributable 1132.WTF package for every platform.
#
#   tools/build_all.sh                build all five packages into dist/
#   tools/build_all.sh windows macos  build only the named ones
#   tools/build_all.sh --no-brand     skip regenerating icons
#
# Platform names: windows, macos, linux, android, ios ("mac" also works)
#
# Output: dist/1132.WTF-<platform>-<version>.zip plus dist/SHA256SUMS
#
# The Android APK is included when one has already been built, or when the
# Android SDK is available for this script to build one. iOS ships as an Xcode
# project, because only a Mac can compile it.

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

VERSION="$(python3 -c "import json;print(json.load(open('brand/brand.json'))['version'])" 2>/dev/null || printf '1.0.0')"
DIST="$REPO_ROOT/dist"
STAGE="$DIST/.stage"

REBUILD_BRAND=1
REQUESTED=()

# The canonical platform names, in the order they are built. Anything that
# invokes this script by name is checked against this list by
# tests/test_packages.sh.
PLATFORMS=(windows macos linux android ios)

while [ $# -gt 0 ]; do
  case "$1" in
    --no-brand) REBUILD_BRAND=0; shift ;;
    --list-platforms)
      printf '%s\n' "${PLATFORMS[@]}"
      exit 0
      ;;
    -h | --help)
      printf '%s\n' "Usage: $0 [--no-brand] [--list-platforms] [platform...]"
      printf '%s\n' "Platforms: ${PLATFORMS[*]}"
      exit 0
      ;;
    # "mac" is accepted as an alias, but macos is canonical: it is what the
    # staged folder and the published zip are both named.
    mac | macos) REQUESTED+=(macos); shift ;;
    windows | linux | android | ios) REQUESTED+=("$1"); shift ;;
    *)
      printf '%s\n' "Unknown argument: $1" >&2
      printf '%s\n' "Platform names: ${PLATFORMS[*]}" >&2
      exit 2
      ;;
  esac
done

if [ "${#REQUESTED[@]}" -eq 0 ]; then
  REQUESTED=("${PLATFORMS[@]}")
fi

wanted() {
  local name="$1" item
  for item in "${REQUESTED[@]}"; do
    [ "$item" = "$name" ] && return 0
  done
  return 1
}

step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '    \033[33mnote:\033[0m %s\n' "$*"; }

if ! command -v zip >/dev/null 2>&1; then
  printf '%s\n' "zip is required. Install it and run again." >&2
  exit 1
fi

printf '1132.WTF packager\n'
printf 'version: %s\n' "$VERSION"

rm -rf "$STAGE"
mkdir -p "$DIST" "$STAGE"

# --------------------------------------------------------------------- brand

if [ "$REBUILD_BRAND" -eq 1 ]; then
  step "Regenerating brand assets"
  if python3 -c "import PIL" >/dev/null 2>&1; then
    python3 brand/build_brand.py >/dev/null && note "icons rebuilt from brand/brand.json"
  else
    warn "Pillow is not installed, using the committed assets as they are"
    warn "install it with: pip3 install Pillow"
  fi
else
  step "Using the committed brand assets"
fi

# Windows text files need CRLF, or Notepad shows one long line and cmd.exe can
# mis-parse a .bat that was saved with Unix endings.
to_crlf() {
  local file="$1"
  python3 - "$file" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
data = p.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
p.write_bytes(data)
PY
}

package() {
  # package <platform> <staged-dir-name>
  local platform="$1" name="$2"
  local zip_path="$DIST/1132.WTF-$platform-$VERSION.zip"
  rm -f "$zip_path"
  ( cd "$STAGE" && zip -q -r -y "$zip_path" "$name" ) || return 1
  note "wrote dist/$(basename "$zip_path") ($(wc -c <"$zip_path" | tr -d ' ') bytes)"
}

# ------------------------------------------------------------------- windows

if wanted windows; then
  step "Windows"
  target="$STAGE/1132.WTF-windows"
  mkdir -p "$target"
  cp -r platforms/windows/. "$target/"
  cp brand/out/1132.WTF.ico "$target/assets/1132.WTF.ico"
  cp brand/out/png/icon_256.png "$target/assets/1132.WTF.png"
  cp docs/ENGINE.md "$target/ENGINE.md"

  while IFS= read -r file; do
    to_crlf "$file"
  done < <(find "$target" -type f \( -name '*.bat' -o -name '*.vbs' -o -name '*.ps1' -o -name '*.md' \))
  note "line endings converted to CRLF"

  package windows "1132.WTF-windows"
fi

# ----------------------------------------------------------------------- mac

if wanted macos; then
  step "macOS"
  target="$STAGE/1132.WTF-macos"
  mkdir -p "$target"
  cp -r platforms/macos/. "$target/"
  cp brand/out/AppIcon.icns "$target/1132.WTF.app/Contents/Resources/AppIcon.icns"
  cp docs/ENGINE.md "$target/ENGINE.md"

  # The bundle will not launch without these bits set.
  chmod +x "$target/1132.WTF.app/Contents/MacOS/1132.WTF"
  chmod +x "$target/1132.WTF.app/Contents/Resources/1132wtf-engine.sh"
  chmod +x "$target/1132.WTF.app/Contents/Resources/1132wtf-session.sh"
  chmod +x "$target/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa"
  chmod +x "$target"/*.command "$target/allow-macos.sh"
  note "executable bits set on the app, helpers, and .command files"

  package macos "1132.WTF-macos"
fi

# --------------------------------------------------------------------- linux

if wanted linux; then
  step "Linux"
  target="$STAGE/1132.WTF-linux"
  mkdir -p "$target"
  cp -r platforms/linux/. "$target/"
  rm -rf "$target/icons"
  mkdir -p "$target/icons"
  cp -r brand/out/linux/hicolor "$target/icons/"
  cp docs/ENGINE.md "$target/ENGINE.md"

  chmod +x "$target/1132wtf" "$target/1132wtf-gui" "$target/install.sh" "$target/uninstall.sh"
  note "executable bits set on the engine, gui, and installers"

  package linux "1132.WTF-linux"

  # A tarball as well, because it preserves permissions on every extractor and
  # is what most Linux users expect.
  tar_path="$DIST/1132.WTF-linux-$VERSION.tar.gz"
  rm -f "$tar_path"
  ( cd "$STAGE" && tar -czf "$tar_path" "1132.WTF-linux" ) &&
    note "wrote dist/$(basename "$tar_path") ($(wc -c <"$tar_path" | tr -d ' ') bytes)"
fi

# ------------------------------------------------------------------- android

if wanted android; then
  step "Android"
  target="$STAGE/1132.WTF-android"
  mkdir -p "$target"

  # Source, so the app can be rebuilt or audited.
  mkdir -p "$target/source"
  cp -r platforms/android/. "$target/source/" 2>/dev/null || true
  rm -rf "$target/source/build" "$target/source/app/build" "$target/source/.gradle"
  rm -f "$target/source/keystore.properties" "$target/source"/*.keystore "$target/source"/*.apk
  cp docs/MOBILE.md "$target/MOBILE.md"
  cp platforms/android/README.md "$target/README.md"
  cp platforms/android/START_HERE.txt "$target/START_HERE.txt"

  # The installable APK, built now if the SDK is around.
  apk=""
  for candidate in \
    platforms/android/1132.WTF-1.0.0-release.apk \
    platforms/android/app/build/outputs/apk/release/app-release.apk \
    platforms/android/app/build/outputs/apk/debug/app-debug.apk
  do
    [ -f "$candidate" ] && { apk="$candidate"; break; }
  done

  if [ -z "$apk" ] && { [ -n "${ANDROID_HOME:-}" ] || [ -n "${ANDROID_SDK_ROOT:-}" ]; }; then
    note "no APK found, building one"
    ( cd platforms/android && ./build-apk.sh >/dev/null 2>&1 ) || true
    [ -f platforms/android/1132.WTF-1.0.0-release.apk ] &&
      apk="platforms/android/1132.WTF-1.0.0-release.apk"
  fi

  if [ -n "$apk" ]; then
    cp "$apk" "$target/1132.WTF-$VERSION.apk"
    note "included $(basename "$apk") as 1132.WTF-$VERSION.apk"
  else
    warn "no APK included: the Android SDK was not available to build one"
    warn "run platforms/android/build-apk.sh with ANDROID_HOME set, then repackage"
  fi

  chmod +x "$target/source/gradlew" "$target/source/build-apk.sh" 2>/dev/null || true
  package android "1132.WTF-android"
fi

# ----------------------------------------------------------------------- ios

if wanted ios; then
  step "iOS"
  target="$STAGE/1132.WTF-ios"
  mkdir -p "$target"
  cp -r platforms/ios/. "$target/"
  rm -rf "$target/build"
  cp docs/MOBILE.md "$target/MOBILE.md"
  chmod +x "$target/build-ios.sh"
  note "Xcode project staged; only a Mac can compile it into an app"
  package ios "1132.WTF-ios"
fi

# ------------------------------------------------------------------ checksums

step "Checksums"
( cd "$DIST" && rm -f SHA256SUMS &&
  find . -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' \) -printf '%f\n' |
  sort | xargs -r sha256sum >SHA256SUMS ) &&
  note "wrote dist/SHA256SUMS"

rm -rf "$STAGE"

step "Done"
printf '\n'
( cd "$DIST" && ls -la -- ./*.zip ./*.tar.gz ./SHA256SUMS 2>/dev/null )
printf '\n'
