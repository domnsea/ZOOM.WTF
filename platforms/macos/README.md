# 1132.WTF for macOS

Zoom error 1132, fixed.

Runs on macOS 10.13 and newer, on both Intel and Apple Silicon. The app is
shell based, so there is no architecture-specific binary and nothing to
compile.

## How to use

Open `START_HERE.txt`. Short version:

STEP 1 - Right-click **`STEP 1 - OPEN FRESH ZOOM.command`** → Open → Open

STEP 2 - Type the random name into Zoom Join. Type the meeting #.

If you want it in Applications instead, right-click **`INSTALL_TO_APPLICATIONS.command`**.

If macOS says the author cannot be verified, that is normal. Click Done, then
System Settings → Privacy & Security → Open Anyway. Or open `OPEN_ME_FIRST.txt`.

## The two steps

| Step | What it does | Admin password |
|---|---|---|
| **STEP 1 OPEN FRESH ZOOM** | Opens Zoom as a throwaway user on this desktop so Join is not your Mac login | yes, once |
| **STEP 2 CLOSE AND CLEAN** | Deletes the throwaway user and restores your regular Zoom | yes, once |

### What level 1 erases

Each item is **moved** into a timestamped backup, never deleted outright. The
list is longer than it used to be, because Zoom keeps the display name,
meeting history ("Join new room?"), and signed-in account in more than the
main Application Support folder:

```
~/Library/Application Support/zoom.us
~/Library/Application Support/Zoom
~/Library/Preferences/us.zoom.xos.plist
~/Library/Preferences/us.zoom.config.plist
~/Library/Caches/us.zoom.xos
~/Library/Caches/com.zoom.us
~/Library/Cookies/us.zoom.xos.binarycookies
~/Library/Saved Application State/us.zoom.xos.savedState
~/Library/HTTPStorages/us.zoom.xos
~/Library/Logs/zoom.us
~/Library/WebKit/us.zoom.xos
~/Library/Containers/us.zoom.xos
~/Library/Group Containers/*zoom*
~/Library/LaunchAgents/*zoom*   (ZoomOpener — this relaunches the old session)
~/.zoomus
```

It also:

- quits **CptHost, ZoomOpener, aomhost, and the updater**, not just `zoom.us`
- clears every Zoom domain out of `cfprefsd` and kills that daemon so the old
  name is not written straight back
- **loop-deletes** every keychain item labeled or serviced `zoom.us` /
  `us.zoom.xos` / `Zoom` (one `delete-generic-password` call only removes one
  item; leftovers are what signed people back in as the previous name)
- opens Zoom on this desktop with AppleScript `activate` and `open -a`
  (not `open -n`, and not a custom data directory — both make Mac Zoom
  exit or open with no window)

Fix now also asks for the name you want Zoom to show, and an optional meeting
ID. If you give both, Zoom is opened with `uname=` so it cannot prefill your
Mac login name.

**Undo last fix** puts the most recent backup back. Backups are in
`~/Library/Application Support/1132.WTF/backups`.

## Files in this package

| File | Role |
|---|---|
| `START_HERE.txt` | the only file you need to read |
| `1132.WTF.app` | the app |
| `INSTALL_TO_APPLICATIONS.command` | copies it to /Applications and de-quarantines it |
| `OPEN_LOGS.command` | opens the log folder |
| `REMOVE_AUTOSTART.command` | stops it running at login |
| `UNINSTALL.command` | removes the app, login item, and optionally its data |

## Command line

The app bundle is also its own CLI:

```bash
/Applications/1132.WTF.app/Contents/MacOS/1132.WTF status
/Applications/1132.WTF.app/Contents/MacOS/1132.WTF fix
/Applications/1132.WTF.app/Contents/MacOS/1132.WTF restore
```

With no arguments it shows the chooser. With `--background` it runs a level 1
reset silently, which is what the login item uses.

## When it does not work

Run **Status** first, then read this:

| Symptom | What is really happening | What helps |
|---|---|---|
| Zoom still opens with your old name | Keychain / iCloud Keychain signed you back in, or Zoom used your **Mac login name** as the guest default | Run STEP 1 again, type a different name, do not sign into the blocked Zoom account. If iCloud Keychain is on, delete Zoom from Keychain Access |
| "Join new room?" after typing a meeting ID | Meeting history was still on disk (helpers or Group Containers survived an older wipe) | This build wipes those. Re-download, run STEP 1, do not open Zoom from the Dock first |
| 1132 comes back immediately | The block is on your **IP address** or this Mac's hardware id | Phone hotspot or VPN. This app randomizes Wi-Fi MAC and computer name; it cannot rewrite the logic-board serial |
| No account on this Mac can join, but your phone can | The block is on your **IP address** | A VPN, or a phone hotspot |
| "Zoom is not installed on this Mac" | The client is somewhere Spotlight cannot see | Install Zoom from zoom.us, then run STEP 1 again |
| Zoom will not quit | Another app is holding a Zoom window | Force Quit Zoom, then run STEP 1 again |

No app running on your Mac can un-ban a server-side Zoom account. When that is
what is happening, Status says so rather than pretending otherwise.

## Logs

```
~/Library/Logs/1132.WTF
```

One `engine_<timestamp>.log` per run.
