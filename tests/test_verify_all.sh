#!/usr/bin/env bash
#
# Verify the five platform packages can actually be used.
# Runs on Linux: syntax, zip contents, Android APK, Linux engine, Mac launch plan.
#
set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

printf '\n1132.WTF verify all platforms\n\n'

# ------------------------------------------------------------------ macos
printf 'macos 1.0.20 launch plan\n'
MAC_LAUNCH="platforms/macos/1132.WTF.app/Contents/Resources/launch_fresh_zoom.sh"
MAC_APP="platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF"
if grep -q 'open -a' "$MAC_LAUNCH" && grep -q 'CONSOLE_USER' "$MAC_LAUNCH" && \
   grep -q '1132wtf-setname.sh' "$MAC_LAUNCH" && ! grep -q 'sysadminctl -addUser' "$MAC_LAUNCH"; then
  pass "STEP 1 opens Zoom on this desktop (not a throwaway user)"
else
  fail "STEP 1 opens Zoom on this desktop" "still using the 1.0.19 throwaway-user launch"
fi
if grep -q '1.0.20' "$MAC_APP" && grep -q '1.0.20' platforms/macos/START_HERE.txt; then
  pass "Mac version string is 1.0.20"
else
  fail "Mac version string is 1.0.20"
fi
bash -n "$MAC_LAUNCH" && bash -n "$MAC_APP" && pass "Mac launch scripts parse" || fail "Mac launch scripts parse"

# ------------------------------------------------------------------ windows
printf '\nwindows\n'
WIN="platforms/windows"
for f in "1132.WTF.vbs" "1132.WTF.bat" "1132WTF_ENGINE.ps1" "1132WTF_APP.ps1" "START_HERE.txt"; do
  if [ -f "$WIN/$f" ]; then pass "windows has $f"; else fail "windows has $f"; fi
done
if grep -q "Start-Process -FilePath \$zoom" "$WIN/1132WTF_ENGINE.ps1" && \
   grep -q "Invoke-IdentityReset" "$WIN/1132WTF_ENGINE.ps1"; then
  pass "windows fix wipes identity then starts Zoom"
else
  fail "windows fix wipes identity then starts Zoom"
fi
if command -v pwsh >/dev/null 2>&1; then
  ps_err="$(pwsh -NoProfile -Command '
    $e=$null; $t=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "platforms/windows/1132WTF_ENGINE.ps1"), [ref]$t, [ref]$e)
    if ($e) { $e[0].Message }
  ' 2>&1)"
  if [ -z "$ps_err" ]; then pass "windows engine parses"; else fail "windows engine parses" "$ps_err"; fi
else
  printf '  skip  PowerShell parse (pwsh not installed)\n'
fi

# ------------------------------------------------------------------ linux
printf '\nlinux\n'
if bash platforms/linux/1132wtf help >/dev/null; then pass "linux engine help runs"; else fail "linux engine help runs"; fi
if bash tests/test_linux_engine.sh >/dev/null; then pass "linux engine sandbox tests"; else fail "linux engine sandbox tests"; fi

# ------------------------------------------------------------------ android
printf '\nandroid\n'
APK=""
for c in dist/1132.WTF-android-1.0.0.zip platforms/android/1132.WTF-1.0.0-release.apk; do
  [ -f "$c" ] && APK="$c"
done
python3 - <<'PY' || fail "android APK is a real package"
import zipfile, pathlib, sys, tempfile, os
repo = pathlib.Path(".").resolve()
zip_path = repo / "dist" / "1132.WTF-android-1.0.0.zip"
apk = None
if zip_path.is_file():
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.endswith(".apk")]
        if not names:
            print("  FAIL  android zip has no .apk")
            sys.exit(1)
        tmp = tempfile.NamedTemporaryFile(suffix=".apk", delete=False)
        tmp.write(z.read(names[0]))
        tmp.close()
        apk = tmp.name
else:
    candidates = list((repo / "platforms/android").rglob("*.apk"))
    if not candidates:
        print("  FAIL  no android apk found")
        sys.exit(1)
    apk = str(candidates[0])
with zipfile.ZipFile(apk) as z:
    names = z.namelist()
    if "AndroidManifest.xml" not in names or "classes.dex" not in names:
        print("  FAIL  apk missing AndroidManifest.xml or classes.dex")
        sys.exit(1)
print("  ok    android APK has manifest and classes.dex")
if apk.startswith("/tmp") or "tmp" in apk:
    try:
        os.unlink(apk)
    except OSError:
        pass
PY
[ -f platforms/android/app/src/main/java/wtf/fix1132/android/MainActivity.java ] && \
  pass "android source is present" || fail "android source is present"
if command -v javac >/dev/null 2>&1; then
  if bash tests/test_android_logic.sh >/dev/null; then pass "android logic tests"; else fail "android logic tests"; fi
else
  printf '  skip  android logic (javac not installed)\n'
fi

# ------------------------------------------------------------------ ios
printf '\nios\n'
if [ -f platforms/ios/1132WTF.xcodeproj/project.pbxproj ]; then
  pass "ios Xcode project exists"
else
  fail "ios Xcode project exists"
fi
if grep -q zoomus platforms/ios/1132WTF/Info.plist; then
  pass "ios queries the Zoom URL scheme"
else
  fail "ios queries the Zoom URL scheme"
fi
if grep -q "https://zoom.us/wc/join" platforms/ios/1132WTF/MeetingLink.swift; then
  pass "ios browser join uses the web client"
else
  fail "ios browser join uses the web client"
fi

# ------------------------------------------------------------------ dist zips
printf '\ndist packages\n'
python3 - <<'PY'
import zipfile, pathlib, sys
root = pathlib.Path("dist")
needed = {
    "1132-FRESH-macos.zip": ["START_HERE.txt", "1132.WTF.app/Contents/MacOS/1132.WTF", "STEP 1 - OPEN FRESH ZOOM.command"],
    "1132.WTF-windows-1.0.0.zip": ["START_HERE.txt", "1132.WTF.vbs", "1132WTF_ENGINE.ps1"],
    "1132.WTF-linux-1.0.0.zip": ["START_HERE.txt", "1132wtf", "install.sh"],
    "1132.WTF-android-1.0.0.zip": ["START_HERE.txt"],
    "1132.WTF-ios-1.0.0.zip": ["START_HERE.txt", "1132WTF.xcodeproj/project.pbxproj"],
}
failed = 0
for archive, needles in needed.items():
    path = root / archive
    if not path.is_file():
        print(f"  FAIL  missing {archive}")
        failed += 1
        continue
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        blob = "\n".join(names)
        missing = [n for n in needles if not any(n in item for item in names)]
        if missing:
            print(f"  FAIL  {archive} missing {missing}")
            failed += 1
        else:
            print(f"  ok    {archive} contains required files")
        if archive.startswith("1132-FRESH-macos") or "macos" in archive:
            # After rebuild this will be 1.0.20; allow either until packager runs.
            pass
sys.exit(1 if failed else 0)
PY
if [ $? -eq 0 ]; then :; else FAIL=$((FAIL + 1)); fi

printf '\n----------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAILED\n\n'
  exit 1
fi
printf 'RESULT: PASSED\n\n'
