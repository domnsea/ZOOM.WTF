# Built packages

These are the finished, ready-to-run 1132.WTF packages. Nothing here needs
compiling.

| File | Platform | Then run |
|---|---|---|
| `1132.WTF-windows-1.0.0.zip` | Windows 10 and 11 | `1132.WTF.vbs` |
| `1132.WTF-macos-1.0.0.zip` | macOS 10.13+, Intel and Apple Silicon | `INSTALL_TO_APPLICATIONS.command` |
| `1132.WTF-linux-1.0.0.tar.gz` | any distribution | `./install.sh` |
| `1132.WTF-linux-1.0.0.zip` | same, for people who prefer zip | `./install.sh` |
| `1132.WTF-android-1.0.0.zip` | Android 5.0+ | the `.apk` inside |
| `1132.WTF-ios-1.0.0.zip` | iOS 16+ | open `1132WTF.xcodeproj` in Xcode |
| `SHA256SUMS` | checksums for all of the above | see below |

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

**macOS** will refuse to open the app on the first try, saying it cannot be
checked for malicious software. That is Gatekeeper reacting to an app not signed
with a paid Apple Developer certificate. `INSTALL_TO_APPLICATIONS.command`
clears the quarantine flag for you; if macOS still objects, right-click the app
in Applications and choose **Open** once.

**Windows** may block the scripts because they came out of a downloaded zip.
Right-click the zip, choose Properties, tick **Unblock**, then extract it again.

## Rebuilding these

```bash
tools/build_all.sh
```

The packager converts Windows files to CRLF, preserves the executable bits the
macOS app bundle needs, ships Linux as both a tarball and a zip, embeds the
Android APK when the SDK can build one, and rewrites `SHA256SUMS`.
