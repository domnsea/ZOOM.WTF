<p align="center">
  <img src="brand/out/wordmark.png" alt="1132.WTF - Zoom error 1132, fixed." width="620">
</p>

# 1132.WTF

Zoom error 1132, fixed. Five platforms, one behaviour, no pretending.

## Download

These links save the file. They do **not** go through `MAIN` (that branch does
not have the packages yet, so those URLs 404) and they do **not** go through a
pull-request diff (GitHub renders every zip there as "Binary file not shown"
with no download button).

| Platform | Download | Then run |
|---|---|---|
| **Windows** | [1132.WTF-windows-1.0.0.zip](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/1132.WTF-windows-1.0.0.zip) | `1132.WTF.vbs` |
| **macOS** | [1132-FRESH-macos.zip](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/1132-FRESH-macos.zip) | `INSTALL_TO_APPLICATIONS.command` |
| **Linux** | [1132.WTF-linux-1.0.0.tar.gz](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/1132.WTF-linux-1.0.0.tar.gz) | `./install.sh` |
| **Android** | [1132.WTF-android-1.0.0.zip](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/1132.WTF-android-1.0.0.zip) | the `.apk` inside |
| **iOS** | [1132.WTF-ios-1.0.0.zip](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/1132.WTF-ios-1.0.0.zip) | `1132WTF.xcodeproj` in Xcode |
| | [SHA256SUMS](https://github.com/domnsea/ZOOM.WTF/releases/latest/download/SHA256SUMS) | `sha256sum -c SHA256SUMS` |

If a Release is not up yet, the same files are on this branch:

| Platform | Direct file |
|---|---|
| Windows | [dist/1132.WTF-windows-1.0.0.zip](dist/1132.WTF-windows-1.0.0.zip) |
| macOS | [dist/1132-FRESH-macos.zip](dist/1132-FRESH-macos.zip) |
| Linux | [dist/1132.WTF-linux-1.0.0.tar.gz](dist/1132.WTF-linux-1.0.0.tar.gz) |
| Android | [dist/1132.WTF-android-1.0.0.zip](dist/1132.WTF-android-1.0.0.zip) |
| iOS | [dist/1132.WTF-ios-1.0.0.zip](dist/1132.WTF-ios-1.0.0.zip) |

On a `dist/` file page, use **Download raw file**. GitHub cannot preview a zip,
so there is no preview button.

```bash
sha256sum -c SHA256SUMS      # shasum -a 256 -c SHA256SUMS on macOS
```

Or build them yourself with `tools/build_all.sh`.

## How to use

Every package has a `START_HERE.txt`. Same three lines on every platform.

### Windows

STEP 1 - Unzip. Double-click `1132.WTF.vbs`

STEP 2 - Click **STEP 1 - Fix Zoom**

LAUNCH - Join. Do not sign in as the old account.

### macOS

STEP 1 - Right-click `INSTALL_TO_APPLICATIONS.command` → Open → Open

STEP 2 - Click **STEP 1 - Fix Zoom**

LAUNCH - Window must say **1132 FRESH 1.0.22**. Use **STEP 1 - OPEN FRESH ZOOM.command**. Lime icon.

### Linux

STEP 1 - Run `./install.sh`

STEP 2 - Open 1132.WTF from your launcher

LAUNCH - Click **STEP 1 - Fix Zoom**

### Android

STEP 1 - Open the `.apk`. Allow install.

STEP 2 - Open 1132.WTF

LAUNCH - Do **STEP 1 - Clear Zoom** on the screen. Join as a guest.

### iOS

STEP 1 - Open `1132WTF.xcodeproj` in Xcode (needs a Mac)

STEP 2 - Press Run on your iPhone

LAUNCH - Do **STEP 1 - Clear Zoom** on the screen. Join as a guest.

If STEP 1 still fails, use STEP 2, then STEP 3 / LAUNCH. Stop when you are in
the meeting.

## What error 1132 actually is

Zoom shows `1132` when you have been blocked. The block is not attached to your
name — it is attached to a handful of identifiers, and **which one it is decides
whether anything on your computer can help**:

| Identifier | Where it lives | Can 1132.WTF reset it? |
|---|---|---|
| Zoom client device id | Zoom's data folder on your machine | **yes** |
| Your operating-system user | your machine | **yes**, on desktop |
| Your Zoom account | Zoom's servers | no, and neither can anything else you install |
| Wi-Fi MAC / computer name | this Mac | **yes**, for this session on macOS |
| Your IP address | your network | no, but a VPN or hotspot can |
| Logic-board serial / hardware UUID | this Mac's firmware | no |

The two rows it can reset are the two that are actually on your machine, and
they are the most common cause. For the other two, the app tells you plainly
that the problem is elsewhere and what would work instead. That is the whole
design principle here: an app running on your laptop cannot un-ban a
server-side account, and saying so beats looking busy.

## The three levels

Every platform implements the same escalating levels, and you stop as soon as
you are back in the meeting.

**Level 1 — reset.** Quit Zoom, back up and erase its local identity (data
directory, preferences, caches, cookies, saved state), relaunch it against an
empty profile. This clears the client device id, which is what 1132 keys off
most often. No administrator rights.

**Level 2 — rotate.** Create a throwaway operating-system user and run Zoom as
that user, so Zoom sees a completely different machine-local identity. Three
rotating slots, oldest destroyed before reuse, so no more than two ever exist.
Needs administrator rights, and desktop only.

**Level 3 — bypass.** Join in a fresh private browser session. Zoom's web client
carries none of the native client's fingerprint, so this is what works when the
first two do not. Available everywhere, including both phones.

Full contract: **[docs/ENGINE.md](docs/ENGINE.md)**.

## What each platform can honestly do

Sandboxing, not ambition, decides this. Phones cannot reach into another app's
data or create users, and the apps say so rather than faking it.

| Level | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| 1 Reset local identity | automatic | automatic | automatic | guided | guided |
| 2 Throwaway OS user | automatic | semi-automatic | automatic | guided | **impossible** |
| 3 Fresh browser session | automatic | automatic | automatic | **automatic** | **automatic** |

*Guided* means the app opens the one screen that can do it and spells out each
tap. *Impossible* means the platform has no such concept — iOS has no second
user profile at all.

Two places where the platform forced a genuinely different design, rather than a
worse copy of the Windows one:

- **macOS level 2** cannot launch a GUI app as another user on your desktop, so
  instead of pretending, it creates the throwaway account, shows you its
  password, and offers to open the login window for a fast user switch.
- **Mobile level 3** is the strongest thing on either phone, because the app
  owns its own web view storage. Android clears the cookie jar, DOM storage,
  cache and history before every load; iOS uses a non-persistent
  `WKWebsiteDataStore` so the session cannot outlive the screen.

Details and reasoning: **[docs/MOBILE.md](docs/MOBILE.md)**.

## Safety

Every destructive step is reversible and narrowly scoped.

- **Nothing is deleted without a backup first.** Each run writes a timestamped
  backup with a manifest, and `restore` (or "Undo last fix") puts it back.
- **Throwaway accounts live behind a reserved name prefix** (`wtf1132…`), and
  each engine refuses to delete any account whose name does not match. Your own
  account cannot be caught by the rotation.
- **Throwaway accounts are not administrators.** Zoom does not need admin.
- **Passwords are random per run**, 24 characters, and never written to disk or
  into a log. On macOS the password is shown to you, because there you have to
  type it at the login window.
- **One run at a time**, enforced by a lock directory.
- **Everything is logged** in a stable `[LEVEL] message` format.

The Windows engine this was built from shipped three problems that are fixed
here: permanent local **administrator** accounts sharing the hardcoded password
`ZoomTemp123!`, a `Win32_UserProfile` filter that escaped backslashes which were
never there (so profile cleanup silently missed every time), and a macOS build
that only opened Zoom without resetting anything at all.

## Repository layout

```
brand/              brand tokens and the icon generator
  brand.json        names, bundle ids, colours, version - the single source
  build_brand.py    generates the vector master and every platform raster
platforms/
  windows/          PowerShell engine + WinForms app + one-click .bat files
  macos/            1132.WTF.app bundle, installer, uninstaller
  linux/            bash engine, GUI front end, desktop entry, installer
  android/          Gradle project, no dependencies, signed APK build script
  ios/              Xcode project, SwiftUI, no dependencies
docs/
  ENGINE.md         the contract all five platforms implement
  MOBILE.md         what the phones can and cannot do, and why
tests/              test suites, all runnable on Linux
tools/build_all.sh  builds every distributable package into dist/
```

### One source of truth for branding

`brand/build_brand.py` defines the seven-segment "1132" geometry once and emits
the vector master **and** every platform raster from it: the multi-frame `.ico`,
a PNG-based `.icns` written byte by byte, Android mipmaps for five densities
plus adaptive-icon layers, the iOS asset catalog, and the freedesktop hicolor
theme. Nothing is traced by hand, so no platform's icon can drift from another's.

## Tests

All four suites run on Linux, with no Mac, no phone, and no emulator.

```bash
tests/test_linux_engine.sh     # 48 checks: end-to-end against a throwaway HOME
tests/test_android_logic.sh    # 28 checks: meeting link parsing on a plain JDK
tests/test_ios_logic.sh        # 27 checks: the same cases, via the Swift toolchain
tests/test_packages.sh         # cross-platform integrity and safety invariants
```

`test_linux_engine.sh` exercises the real engine against a throwaway `HOME` and
a stub Zoom binary, so it needs neither root nor a Zoom install. It is what
caught the backup-collision bug: backup directories were named from a
second-resolution timestamp, so two runs in the same second shared a directory
and the second deleted the first's manifest, making restore silently impossible.

The Android and iOS suites run the **same table of cases** against both
implementations of meeting link parsing, which is what stops the two platforms
quietly disagreeing about what a meeting link means.

`test_packages.sh` checks the things that rot in a five-platform repository:
leftover old branding, missing icon sizes, `CFBundleExecutable` naming a file
that does not exist, manifests forgetting to declare the Zoom package so
detection always answers "no", verb parity between the three desktop engines,
and the safety invariants above.

## Building

```bash
tools/build_all.sh                    # all five, into dist/
tools/build_all.sh windows linux      # just those two
tools/build_all.sh --no-brand         # skip regenerating icons
```

The packager converts Windows files to CRLF, preserves the executable bits macOS
needs inside the `.app` bundle, ships Linux as both a zip and a tarball, embeds
the Android APK when one can be built, and writes `dist/SHA256SUMS`.

Per-platform build requirements:

| Platform | Needs |
|---|---|
| Windows, macOS, Linux | nothing, they are scripts |
| Android | Android SDK 34 + JDK 17, then `platforms/android/build-apk.sh` |
| iOS | a Mac with Xcode, then `platforms/ios/build-ios.sh` |

iOS is the one platform that cannot be compiled here. Apple's toolchain only
runs on macOS, so the package ships as a complete, dependency-free Xcode project
that opens and runs.
