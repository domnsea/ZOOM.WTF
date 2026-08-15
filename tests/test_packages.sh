#!/usr/bin/env bash
#
# Integrity checks across all five platform packages.
#
# These exist because a five-platform repository drifts silently: one platform
# gets a fix, another keeps the bug; one gets rebranded, another keeps the old
# name; an icon is regenerated for four platforms and not the fifth. Each check
# below is something that has actually gone wrong in projects shaped like this.
#
# Usage: tests/test_packages.sh

set -u
set -o pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

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
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description" "failed: $*"; fi
}

check_grep() {
  # check_grep <description> <pattern> <file>
  if grep -qF -- "$2" "$3" 2>/dev/null; then
    pass "$1"
  else
    fail "$1" "$3 does not contain: $2"
  fi
}

# Runs a Python block fed on stdin and folds its exit status into the tally.
# The block prints its own ok/FAIL lines.
python_check() {
  if python3 -; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

printf '\n1132.WTF package integrity\n\n'

# ------------------------------------------------------------ 1. branding

printf 'branding\n'

# The packages are a rebrand of an app previously called ZOOM.WTF. Any leftover
# is a user-visible mistake, so the only allowed mentions are in documentation
# that deliberately explains the history.
leftovers=""
while IFS= read -r file; do
  case "$file" in
    ./docs/* | ./README.md | ./tests/* | ./ZOOM.WTF*) continue ;;
  esac
  if grep -qlF "ZOOM.WTF" "$file" 2>/dev/null; then
    leftovers="${leftovers:+$leftovers }$file"
  fi
done < <(find ./platforms ./brand ./tools -type f \
  \( -name '*.sh' -o -name '*.ps1' -o -name '*.bat' -o -name '*.vbs' \
  -o -name '*.md' -o -name '*.java' -o -name '*.swift' -o -name '*.xml' \
  -o -name '*.plist' -o -name '*.json' -o -name '*.desktop' -o -name '*.command' \) 2>/dev/null)

if [ -z "$leftovers" ]; then
  pass "no ZOOM.WTF branding left in any platform package"
else
  fail "no ZOOM.WTF branding left in any platform package" "found in: $leftovers"
fi

for platform in windows macos linux android ios; do
  check "platforms/$platform has a README" test -f "platforms/$platform/README.md"
done

# ------------------------------------------------------------ 2. brand assets

printf '\nbrand assets\n'
check "master SVG exists" test -f brand/out/icon.svg
check "Windows .ico exists" test -f brand/out/1132.WTF.ico
check "macOS .icns exists" test -f brand/out/AppIcon.icns
check "wordmark exists" test -f brand/out/wordmark.png

python_check <<'PY'
import struct, sys, json
from pathlib import Path

problems = []

# ICO must carry every size the launcher and taskbar ask for.
try:
    from PIL import Image
    ico = Image.open("brand/out/1132.WTF.ico")
    sizes = {w for w, _ in ico.info["sizes"]}
    for needed in (16, 32, 48, 256):
        if needed not in sizes:
            problems.append(f"ico is missing the {needed}px frame")
except ImportError:
    print("  skip  ico frame check (Pillow not installed)")
except Exception as exc:
    problems.append(f"ico unreadable: {exc}")

# ICNS must be a well-formed container, or Finder shows a blank icon.
data = Path("brand/out/AppIcon.icns").read_bytes()
if data[:4] != b"icns":
    problems.append("icns magic is wrong")
elif struct.unpack(">I", data[4:8])[0] != len(data):
    problems.append("icns declared length does not match the file size")
else:
    offset, types = 8, []
    while offset < len(data):
        kind = data[offset:offset + 4].decode("ascii", "replace")
        length = struct.unpack(">I", data[offset + 4:offset + 8])[0]
        if length < 8:
            problems.append(f"icns chunk {kind} has a bad length")
            break
        types.append(kind)
        offset += length
    for needed in ("ic07", "ic08", "ic09", "ic10"):
        if needed not in types:
            problems.append(f"icns is missing the {needed} chunk")

# Android needs every density, or the launcher scales a blurry icon.
for bucket in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    for name in ("ic_launcher.png", "ic_launcher_round.png", "ic_launcher_foreground.png"):
        path = Path(f"platforms/android/app/src/main/res/mipmap-{bucket}/{name}")
        if not path.is_file():
            problems.append(f"android is missing mipmap-{bucket}/{name}")

# iOS asset catalog entries must all resolve to real files.
catalog = Path("platforms/ios/1132WTF/Assets.xcassets/AppIcon.appiconset")
contents = json.loads((catalog / "Contents.json").read_text())
for image in contents["images"]:
    filename = image.get("filename")
    if filename and not (catalog / filename).is_file():
        problems.append(f"ios asset catalog references a missing {filename}")

if problems:
    for problem in problems:
        print(f"  FAIL  {problem}")
    sys.exit(1)
print("  ok    ico, icns, android mipmaps and ios catalog are all complete")
PY

# --------------------------------------------------- 3. desktop verb parity

printf '\ndesktop engines expose the same verbs\n'
WIN_ENGINE="platforms/windows/1132WTF_ENGINE.ps1"
MAC_ENGINE="platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-engine.sh"
LINUX_ENGINE="platforms/linux/1132wtf"

for verb in status fix deep-fix browser restore logs; do
  check_grep "windows engine handles '$verb'" "'$verb'" "$WIN_ENGINE"
  check_grep "macos engine handles '$verb'" "$verb)" "$MAC_ENGINE"
  check_grep "linux engine handles '$verb'" "$verb)" "$LINUX_ENGINE"
done
check_grep "windows engine handles autostart" "autostart-on" "$WIN_ENGINE"
check_grep "macos engine handles autostart" "autostart-on)" "$MAC_ENGINE"
check_grep "linux engine handles autostart" "autostart-on)" "$LINUX_ENGINE"

# ------------------------------------------------- 4. safety invariants

printf '\nsafety invariants hold on every desktop platform\n'

# Rotation must never be able to delete a real user account. Each engine guards
# on a reserved name prefix before deleting anything.
check_grep "windows refuses accounts outside its prefix" "Refusing to delete" "$WIN_ENGINE"
check_grep "macos refuses accounts outside its prefix" "Refusing to act on" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-session.sh
check_grep "linux refuses accounts outside its prefix" "Refusing to delete" "$LINUX_ENGINE"

# Backups must exist before anything is deleted, and restore must be reachable.
check_grep "windows writes a backup manifest" "manifest.txt" "$WIN_ENGINE"
check_grep "macos writes a backup manifest" "manifest.txt" "$MAC_ENGINE"
check_grep "linux writes a backup manifest" "manifest.txt" "$LINUX_ENGINE"

# Backup directories must be unique per run, which is what stopped two runs in
# the same second from destroying each other's manifest.
check_grep "macos claims a unique backup directory" "new_backup_dir" "$MAC_ENGINE"
check_grep "linux claims a unique backup directory" "new_backup_dir" "$LINUX_ENGINE"

# The first macOS wipe only moved a handful of Library paths and then ran
# `open -a`, which reused the old Zoom session. That left the previous
# display name and "Join new room?" meeting history in place.
check_grep "macos wipes group containers" "Group Containers" "$MAC_ENGINE"
check_grep "macos wipes hidden .zoomus dir" ".zoomus" "$MAC_ENGINE"
check_grep "macos kills ZoomOpener" "ZoomOpener" "$MAC_ENGINE"
check_grep "macos kills CptHost" "CptHost" "$MAC_ENGINE"
check_grep "macos force-closes Zoom instead of waiting on quit" "Force-closing Zoom" "$MAC_ENGINE"
if grep -q 'tell application "zoom.us" to quit' "$MAC_ENGINE"; then
  fail "macos does not wait on Zoom's quit dialog" "AppleScript quit is still there and will hang"
else
  pass "macos does not wait on Zoom's quit dialog"
fi
check_grep "macos loop-deletes keychain items" "delete-generic-password" "$MAC_ENGINE"
check_grep "macos flushes cfprefsd" "cfprefsd" "$MAC_ENGINE"
check_grep "macos can pass a guest display name" "uname=" "$MAC_ENGINE"
check_grep "macos session helper prepares a throwaway user" "--prepare" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-session.sh
check_grep "macos app shows version 1.0.14 so an old copy is obvious" "1.0.14" \
  platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF
check_grep "macos window title is 1132 FRESH" "1132 FRESH" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa
check_grep "macos opens a clean Zoom app" "launch_zoom_temp_profile" "$MAC_ENGINE"
check_grep "macos GUI is a branded window" "1132wtf-gui.jxa" \
  platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF
check_grep "macos GUI shows the 1132 logo" "setIcon" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa
check_grep "macos GUI lists STEP 1 - Fix Zoom" "STEP 1 - Fix Zoom" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa
if grep -q "Join in browser" platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa \
  platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF; then
  fail "macos window does not offer browser join" "the window still has Join in browser"
else
  pass "macos window does not offer browser join"
fi
if grep -qi safari platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa \
  platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF; then
  fail "macos window does not mention Safari" "the window still talks about Safari"
else
  pass "macos window does not mention Safari"
fi
check_grep "macos hides the throwaway user from the login list" "IsHidden" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-session.sh
check_grep "macos deletes the throwaway user after Zoom quits" "Zoom exited. Deleting" \
  platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-session.sh
if grep -E 'open -na.*[Zz]oom|open -na "\$zoom' "$MAC_ENGINE"; then
  fail "macos does not start a second Zoom with open -n" \
    "open -na starts a second instance that often has no window"
else
  pass "macos does not start a second Zoom with open -n"
fi
if grep -q -- '--data=' "$MAC_ENGINE"; then
  fail "macos does not pass Zoom a custom data directory" \
    "a custom data directory makes Mac Zoom exit instead of opening"
else
  pass "macos does not pass Zoom a custom data directory"
fi
if grep -vE '^[[:space:]]*#' platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-session.sh | grep -q 'killall'; then
  fail "macos session helper does not kill Zoom" \
    "the watcher used to force-quit zoom.us, which is why Zoom never stayed open"
else
  pass "macos session helper does not kill Zoom"
fi
# STEP 1 / STEP 2 create a temporary Mac user, open Zoom on that empty
# profile, then delete the user when Zoom quits. Never a web page.
python_check <<'PY'
from pathlib import Path
engine = Path("platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-engine.sh").read_text()
launcher = Path("platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF").read_text()
gui = Path("platforms/macos/1132.WTF.app/Contents/Resources/1132wtf-gui.jxa").read_text()
start = engine.find("do_fix()")
end = engine.find("\nlist_backups()", start)
block = engine[start:end]
if "do_fresh_session" not in block:
    raise SystemExit("do_fix must create a temporary user and open Zoom")
if "launch_zoom_temp_profile" not in engine:
    raise SystemExit("engine must open Zoom on the temporary profile")
for banned in ("Safari", "open_join_page", "fromPWA", "Google Chrome", "Firefox"):
    if banned in engine or banned in launcher or banned in gui:
        raise SystemExit(f"Mac app still contains {banned}")
if "$join_url" in engine[engine.find("launch_zoom_temp_profile()"):engine.find("do_wipe_identity()")]:
    raise SystemExit("temp-profile launch must not open a join URL")
print("  ok    macos fix opens Zoom on a temporary user profile")
PY
if grep -q "Switch now" "$MAC_ENGINE"; then
  fail "macos fix does not ask you to switch profiles" "Switch now is still in the engine"
else
  pass "macos fix does not ask you to switch profiles"
fi

# No hardcoded passwords anywhere. The original Windows build shipped one.
if grep -rniE "ZoomTemp123|password *= *['\"][A-Za-z0-9!@#]{6,}['\"]" \
  platforms/ --include='*.ps1' --include='*.sh' --include='*.bat' >/dev/null 2>&1; then
  fail "no hardcoded passwords in any engine" "found a literal password"
else
  pass "no hardcoded passwords in any engine"
fi

# Windows rotation accounts must not be administrators.
if grep -q "Add-LocalGroupMember -Group 'Administrators'" "$WIN_ENGINE"; then
  fail "windows rotation accounts are not administrators" "found an Administrators group add"
else
  pass "windows rotation accounts are not administrators"
fi

# --------------------------------------------------- 5. identifier consistency

printf '\nidentifiers are consistent\n'
check_grep "android gradle applicationId" "wtf.fix1132.android" platforms/android/app/build.gradle
check_grep "android java package" "package wtf.fix1132.android" \
  platforms/android/app/src/main/java/wtf/fix1132/android/MainActivity.java
check_grep "ios bundle id" "wtf.fix1132.ios" platforms/ios/1132WTF.xcodeproj/project.pbxproj
check_grep "macos bundle id" "wtf.fix1132.mac" platforms/macos/1132.WTF.app/Contents/Info.plist
check_grep "macos launch agent matches the bundle id" "wtf.fix1132.mac" \
  platforms/macos/REMOVE_AUTOSTART.command

python_check <<'PY'
import plistlib, sys
from pathlib import Path

problems = []

# CFBundleExecutable must name a file that exists, or macOS refuses to launch
# the bundle with an unhelpful error.
plist = plistlib.loads(Path("platforms/macos/1132.WTF.app/Contents/Info.plist").read_bytes())
executable = plist["CFBundleExecutable"]
if not Path(f"platforms/macos/1132.WTF.app/Contents/MacOS/{executable}").is_file():
    problems.append(f"CFBundleExecutable names {executable}, which does not exist")

# CFBundleIconFile must match the icns basename.
icon = plist["CFBundleIconFile"]
if not Path(f"platforms/macos/1132.WTF.app/Contents/Resources/{icon}.icns").is_file():
    problems.append(f"CFBundleIconFile names {icon}, but {icon}.icns is missing")

# The iOS Info.plist must declare the Zoom scheme, or detection silently
# always answers "not installed".
ios = plistlib.loads(Path("platforms/ios/1132WTF/Info.plist").read_bytes())
if "zoomus" not in ios.get("LSApplicationQueriesSchemes", []):
    problems.append("ios Info.plist does not query the zoomus scheme")
for key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
    if not ios.get(key):
        problems.append(f"ios Info.plist is missing {key}, so the clean room cannot use media")

# The Android manifest must declare the Zoom package for the same reason.
manifest = Path("platforms/android/app/src/main/AndroidManifest.xml").read_text()
if "us.zoom.videomeetings" not in manifest:
    problems.append("android manifest does not query the Zoom package")

if problems:
    for problem in problems:
        print(f"  FAIL  {problem}")
    sys.exit(1)
print("  ok    bundle plists and manifests all reference files and schemes that exist")
PY

# ------------------------------------------------- 6. packager platform names

printf '\npackager platform names\n'

# CI once passed "macos" to a packager that only accepted "mac", which failed the
# build. Any platform name used in a workflow or a README must be one the
# packager actually accepts.
accepted="$(bash tools/build_all.sh --list-platforms 2>/dev/null)"
if [ -z "$accepted" ]; then
  fail "packager reports its platform names" "--list-platforms printed nothing"
else
  pass "packager reports its platform names"

  # Only the workflows are checked, because those are what actually run. Prose
  # in a README would produce false matches on ordinary English words.
  used=""
  while IFS= read -r word; do
    used="${used:+$used }$word"
  done < <(grep -rhoE 'build_all\.sh[^|&;#]*' .github/workflows 2>/dev/null |
    tr ' ' '\n' |
    grep -xE '[a-z]+' |
    sort -u)

  unknown=""
  for word in $used; do
    if ! printf '%s\n' "$accepted" | grep -qx -- "$word"; then
      unknown="${unknown:+$unknown }$word"
    fi
  done

  if [ -z "$unknown" ]; then
    pass "workflows use canonical platform names"
  else
    fail "workflows use canonical platform names" \
      "not in --list-platforms: $unknown (aliases work but should not be relied on)"
  fi
fi

# ----------------------------------------------------------- 7. script syntax

printf '\nevery shell script parses\n'
syntax_bad=""
while IFS= read -r script; do
  bash -n "$script" 2>/dev/null || syntax_bad="${syntax_bad:+$syntax_bad }$script"
done < <(find platforms tools tests -type f \
  \( -name '*.sh' -o -name '*.command' -o -name '1132wtf' -o -name '1132wtf-gui' \) 2>/dev/null)
bash -n "platforms/macos/1132.WTF.app/Contents/MacOS/1132.WTF" 2>/dev/null ||
  syntax_bad="${syntax_bad:+$syntax_bad }macos-app-executable"

if [ -z "$syntax_bad" ]; then
  pass "all shell scripts pass bash -n"
else
  fail "all shell scripts pass bash -n" "failed: $syntax_bad"
fi

# PowerShell is only checkable where pwsh exists, which is not everywhere.
if command -v pwsh >/dev/null 2>&1; then
  PWSH="pwsh"
elif [ -x "$HOME/pwsh/pwsh" ]; then
  PWSH="$HOME/pwsh/pwsh"
else
  PWSH=""
fi

if [ -n "$PWSH" ]; then
  # The single quotes are deliberate: this is PowerShell source, not shell.
  # shellcheck disable=SC2016
  ps_errors="$("$PWSH" -NoProfile -Command '
    $bad = @()
    foreach ($f in @("platforms/windows/1132WTF_ENGINE.ps1","platforms/windows/1132WTF_APP.ps1")) {
      $errors = $null; $tokens = $null
      [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors)
      if ($errors) { $bad += "$f : $($errors[0].Message)" }
    }
    $bad -join "; "
  ' 2>&1)"
  if [ -z "$ps_errors" ]; then
    pass "PowerShell files parse"
  else
    fail "PowerShell files parse" "$ps_errors"
  fi
else
  printf '  skip  PowerShell parse check (pwsh not installed)\n'
fi

# ------------------------------------------------------- 8. docs are wired up

printf '\ndocumentation\n'
check "engine contract exists" test -f docs/ENGINE.md
check "mobile limits are documented" test -f docs/MOBILE.md
check "top level README exists" test -f README.md
check_grep "README links the engine contract" "docs/ENGINE.md" README.md
check_grep "README links the mobile notes" "docs/MOBILE.md" README.md

# ../../raw/MAIN/dist/... 404s until this branch is merged. The download table
# must not use that path: it is why the packages looked undownloadable.
if grep -n 'raw/MAIN/dist' README.md dist/README.md >/dev/null 2>&1; then
  fail "README download links do not point at MAIN (which 404s)" \
    "$(grep -n 'raw/MAIN/dist' README.md dist/README.md)"
else
  pass "README download links do not point at MAIN (which 404s)"
fi

# Every platform README should say what to run first, because that is the only
# thing most people will read.
check_grep "windows README names the launcher" "1132.WTF.vbs" platforms/windows/README.md
check_grep "macos README names the installer" "INSTALL_TO_APPLICATIONS.command" platforms/macos/README.md
check_grep "macos installer can replace a root-owned old app" "with administrator privileges" platforms/macos/INSTALL_TO_APPLICATIONS.command
check_grep "macos installer detects the old AppleScript applet" "OLD Zoom.WTF" platforms/macos/INSTALL_TO_APPLICATIONS.command
check "macos has DELETE_OLD_APP.command" test -f platforms/macos/DELETE_OLD_APP.command

# Every platform must tell the user what to do in the same three lines.
# The first write-up was a wall of text and people could not follow it.
for platform in windows macos linux android ios; do
  start="platforms/$platform/START_HERE.txt"
  check "$platform has START_HERE.txt" test -f "$start"
  check_grep "$platform START_HERE says STEP 1" "STEP 1" "$start"
  check_grep "$platform START_HERE says STEP 2" "STEP 2" "$start"
  check_grep "$platform START_HERE says LAUNCH" "LAUNCH" "$start"
done
check_grep "top-level README has How to use" "## How to use" README.md
check "macos package has OPEN_ME_FIRST.txt for Gatekeeper" test -f platforms/macos/OPEN_ME_FIRST.txt
check_grep "OPEN_ME_FIRST tells them to right-click Open" "Right-click" platforms/macos/OPEN_ME_FIRST.txt
check_grep "OPEN_ME_FIRST has a Terminal paste" "xattr -cr" platforms/macos/OPEN_ME_FIRST.txt
check "macos allow helper exists" test -f platforms/macos/allow-macos.sh
check_grep "linux README names the installer" "install.sh" platforms/linux/README.md
check_grep "android README names the build script" "build-apk.sh" platforms/android/README.md
check_grep "ios README names the project" "1132WTF.xcodeproj" platforms/ios/README.md

# -------------------------------------------------------------------- summary

printf '\n----------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAILED\n\n'
  exit 1
fi
printf 'RESULT: PASSED\n\n'
