# Original ZOOM.WTF uploads

These are the zip files that were in this repository before the 1132.WTF
packages were built. They are kept here, unmodified, so nothing is lost and the
new packages can be compared against what they replaced.

| File | What it was |
|---|---|
| `ZOOM.WTF_windows_app.zip` | first Windows build |
| `ZOOM.WTF_v1_final.zip` | later Windows build, cleaned layout |
| `ZOOM.WTF_WIN.zip` | same contents as `ZOOM.WTF_v1_final.zip` |
| `ZOOM.WTF_mac_app.zip` | first macOS build |
| `ZOOM.WTF_MAC.zip` | later macOS build |
| `ZOOM.WTF_v1_mac.zip` | same contents as `ZOOM.WTF_MAC.zip` |

Six zips, four distinct builds: the Windows and macOS packages were each
uploaded twice under different names.

## What the new packages changed

The Windows engine was the only one that genuinely reset anything, and it had
three problems that are fixed in `platforms/windows`:

- Rotation accounts were created as **local administrators** and all shared the
  hardcoded password `ZoomTemp123!`, which left a permanent admin account with a
  known password on the machine. They are now standard users with a random
  24-character password per run that is never written to disk.
- Profile cleanup called `Win32_UserProfile` with a filter built by
  `$profilePath.Replace('\\', '\\\\')`. In PowerShell single quotes, `'\\'` is
  two literal backslashes, and the paths only ever contain one, so the replace
  did nothing, the filter never matched, and stale profiles were left behind on
  every run.
- Backups did not exist at all, so there was no way back.

The macOS build did not fix 1132. `start.sh` located Zoom and called
`open -a` on it, and nothing else. Launching Zoom is not a reset, so the block
was still in place when it opened. `platforms/macos` implements the real thing.

Linux, Android, and iOS had no build at all.
