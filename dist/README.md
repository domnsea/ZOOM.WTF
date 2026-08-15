# Built packages

These are the finished, ready-to-run 1132.WTF packages. Nothing here needs
compiling.

| File | Platform | Then run |
|---|---|---|
| `1132.WTF-windows-1.0.0.zip` | Windows 10 and 11 | `1132.WTF.vbs` |
| `1132-FRESH-macos.zip` | macOS 10.13+, Intel and Apple Silicon, **1.0.20** | `STEP 1 - OPEN FRESH ZOOM.command` |
| `1132.WTF-linux-1.0.0.tar.gz` | any distribution | `./install.sh` |
| `1132.WTF-linux-1.0.0.zip` | same, for people who prefer zip | `./install.sh` |
| `1132.WTF-android-1.0.0.zip` | Android 5.0+ | the `.apk` inside |
| `1132.WTF-ios-1.0.0.zip` | iOS 16+ | open `1132WTF.xcodeproj` in Xcode |
| `SHA256SUMS` | checksums for all of the above | see below |

## How to use

Every unzipped package has a `START_HERE.txt`. Same three lines everywhere:

STEP 1 - run the installer / launcher named in the table above

STEP 2 - click **STEP 1 - Fix Zoom** (or Clear Zoom on a phone)

LAUNCH - join. Do not sign in as the old account.

If that fails, use STEP 2, then STEP 3 / LAUNCH.

## How to download one

GitHub cannot preview a zip, so there is no preview button on these files, only
a download one. Click the file in the list above this README, then **Download
raw file**.

If you are looking at a **pull request** diff instead, every archive shows as
"Binary file not shown" with no link at all. That is a limitation of the diff
view, not a broken file. Switch to the branch's normal file list, or download
the whole branch as a single zip from the green **Code** button.

For one-click downloads, run the **Release** workflow from the Actions tab. It
verifies these checksums, runs the test suites, and publishes the same files as
release assets.

## Verify what you downloaded

```bash
sha256sum -c SHA256SUMS
```

On macOS:

```bash
shasum -a 256 -c SHA256SUMS
```

Run it in the directory holding the files. Any package you did not download is
reported as missing, which is expected — only the line for the file you actually
have needs to say `OK`.

## Two notes on what your system will say

**macOS** will say the author cannot be verified. That is Gatekeeper, because
the app is not signed with a paid Apple Developer certificate. Open
`OPEN_ME_FIRST.txt` in the zip (plain text, always opens) and follow it:
right-click → Open, or Privacy & Security → Open Anyway, or the Terminal
command in that file. `INSTALL_TO_APPLICATIONS.command` now strips the
download flag and signs this copy locally.

**Windows** may block the scripts because they came out of a downloaded zip.
Right-click the zip, choose Properties, tick **Unblock**, then extract it again.

## Rebuilding these

```bash
tools/build_all.sh
```

The packager converts Windows files to CRLF, preserves the executable bits the
macOS app bundle needs, ships Linux as both a tarball and a zip, embeds the
Android APK when the SDK can build one, and rewrites `SHA256SUMS`.
