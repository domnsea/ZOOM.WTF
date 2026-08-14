#!/usr/bin/env bash
#
# Build a signed, installable 1132.WTF APK.
#
#   ./build-apk.sh            release build, signed, ready to sideload
#   ./build-apk.sh --debug    debug build, no keystore needed
#
# On the first release build this generates a signing keystore. Keep the
# generated keystore and keystore.properties: Android will only accept an
# update to an installed app if it is signed with the same key. Neither file is
# ever committed.

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1

KEYSTORE="1132wtf-release.keystore"
KEY_PROPS="keystore.properties"
KEY_ALIAS="1132wtf"
BUILD_TYPE="release"

[ "${1:-}" = "--debug" ] && BUILD_TYPE="debug"

printf '=== Building 1132.WTF for Android (%s) ===\n\n' "$BUILD_TYPE"

# ------------------------------------------------------------------ toolchain

if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  for candidate in "$HOME/Android/Sdk" "$HOME/android-sdk" "$HOME/Library/Android/sdk"; do
    if [ -d "$candidate" ]; then
      export ANDROID_HOME="$candidate"
      break
    fi
  done
fi
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"

if [ -z "$ANDROID_HOME" ] || [ ! -d "$ANDROID_HOME" ]; then
  cat <<'MESSAGE' >&2
Cannot find the Android SDK.

Install Android Studio, or just the command line tools, then point ANDROID_HOME
at the SDK directory:

  export ANDROID_HOME="$HOME/Android/Sdk"

The SDK needs platform android-34 and build-tools 34.0.0, both of which the
Android Studio setup wizard installs by default.
MESSAGE
  exit 1
fi
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"
printf 'SDK: %s\n' "$ANDROID_HOME"

if ! command -v java >/dev/null 2>&1; then
  printf '%s\n' "Java is required to run Gradle. Install JDK 17 or newer." >&2
  exit 1
fi

GRADLEW="./gradlew"
if [ ! -x "$GRADLEW" ]; then
  printf '%s\n' "gradlew is missing or not executable in $HERE" >&2
  exit 1
fi

# ------------------------------------------------------------------- keystore

if [ "$BUILD_TYPE" = "release" ] && [ ! -f "$KEY_PROPS" ]; then
  printf '\nNo signing key yet, generating one.\n'

  KEYTOOL="keytool"
  command -v "$KEYTOOL" >/dev/null 2>&1 || KEYTOOL="$JAVA_HOME/bin/keytool"
  if ! command -v "$KEYTOOL" >/dev/null 2>&1; then
    printf '%s\n' "keytool was not found. It ships with the JDK." >&2
    exit 1
  fi

  # Random password: nothing about this key needs to be memorable, and it is
  # written to a gitignored file with owner-only permissions.
  PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"

  if ! "$KEYTOOL" -genkeypair -v \
    -keystore "$KEYSTORE" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 -validity 10950 \
    -storepass "$PASSWORD" -keypass "$PASSWORD" \
    -dname "CN=1132.WTF, OU=1132.WTF, O=1132.WTF, C=US" >/dev/null 2>&1; then
    printf '%s\n' "keytool could not create the keystore." >&2
    exit 1
  fi

  umask 077
  {
    printf 'storeFile=%s\n' "$KEYSTORE"
    printf 'storePassword=%s\n' "$PASSWORD"
    printf 'keyAlias=%s\n' "$KEY_ALIAS"
    printf 'keyPassword=%s\n' "$PASSWORD"
  } >"$KEY_PROPS"
  chmod 600 "$KEY_PROPS"

  printf '  created %s\n' "$KEYSTORE"
  printf '  created %s\n' "$KEY_PROPS"
  printf '\n  Keep both files. Updates must be signed with the same key.\n'
fi

# ---------------------------------------------------------------------- build

printf '\nBuilding...\n\n'

if [ "$BUILD_TYPE" = "release" ]; then
  "$GRADLEW" --console=plain assembleRelease || exit 1
  APK="app/build/outputs/apk/release/app-release.apk"
else
  "$GRADLEW" --console=plain assembleDebug || exit 1
  APK="app/build/outputs/apk/debug/app-debug.apk"
fi

if [ ! -f "$APK" ]; then
  printf '\n%s\n' "The build reported success but $APK is missing." >&2
  exit 1
fi

OUT="1132.WTF-1.0.0-$BUILD_TYPE.apk"
cp "$APK" "$OUT"

printf '\n=== Done ===\n'
printf 'APK: %s (%s bytes)\n' "$OUT" "$(wc -c <"$OUT" | tr -d ' ')"

# Report what the APK actually claims, rather than assuming the build was right.
APKANALYZER="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
if [ -x "$APKANALYZER" ]; then
  printf '\nManifest summary\n'
  printf '  package     %s\n' "$("$APKANALYZER" manifest application-id "$OUT" 2>/dev/null || printf '?')"
  printf '  min sdk     %s\n' "$("$APKANALYZER" manifest min-sdk "$OUT" 2>/dev/null || printf '?')"
  printf '  target sdk  %s\n' "$("$APKANALYZER" manifest target-sdk "$OUT" 2>/dev/null || printf '?')"
fi

printf '\nInstall it with:\n'
printf '  adb install -r %s\n' "$OUT"
printf '\nOr copy it to the phone and open it. Android will ask you to allow\n'
printf 'installing from this source, because it did not come from Play.\n'
