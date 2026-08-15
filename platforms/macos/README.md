# 1132.WTF for macOS

Zoom error 1132, fixed.

Runs on macOS 10.13 and newer, on both Intel and Apple Silicon. The app is
shell based, so there is no architecture-specific binary and nothing to
compile.

## Start here

**If macOS says the author cannot be verified**, open `OPEN_ME_FIRST.txt`
(plain text — Gatekeeper never blocks it) and follow it. The short version:

1. Right-click `INSTALL_TO_APPLICATIONS.command` → **Open** → Open
2. Or System Settings → Privacy & Security → **Open Anyway**
3. Or paste the Terminal command from `OPEN_ME_FIRST.txt`

That dialog is Gatekeeper. This app is not signed with a paid Apple Developer
certificate, so macOS treats it like any other file from the internet. It is
not a warning that the app is damaged.

Otherwise:

1. Run **`INSTALL_TO_APPLICATIONS.command`**.
   It copies the app to `/Applications`, clears the download flag, and signs
   this copy locally so Gatekeeper will launch it.
2. Open **`1132.WTF`** from Applications.
3. Pick an action and work down the list. Stop as soon as you are back in the
   meeting.

## The three levels

| Level | What it does | Admin password |
|---|---|---|
| **1 Fix now** | Quits Zoom **and its helpers**, backs up and erases every Zoom identity path, wipes keychain login, reopens Zoom in an empty isolated profile | no |
| **2 Deep fix** | Creates a clean throwaway macOS account. You must **switch** to it — deleting those accounts while staying on this login does nothing | yes |
| **3 Join in browser** | Opens a fresh private browser window so you skip the client entirely | no |

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
- launches a **new** Zoom instance (`open -n`) against an empty `--data=`
  profile, so LaunchServices cannot reuse the old window

Fix now also asks for the name you want Zoom to show, and an optional meeting
ID. If you give both, Zoom is opened with `uname=` so it cannot prefill your
Mac login name.

**Undo last fix** puts the most recent backup back. Backups are in
`~/Library/Application Support/1132.WTF/backups`.

### Why level 2 works differently here than on Windows

On Windows the fixer can launch Zoom as another user on your current desktop.
macOS does not allow that: a GUI app only runs in its own user's session. So
level 2 creates the throwaway account, shows you its password, and offers to
open the login window so you can switch to it with fast user switching.

The accounts are named `wtf1132a`, `wtf1132b`, and `wtf1132c`, used in
rotation. Before reusing a slot the engine deletes the oldest, so at most two
exist at a time, and it refuses to act on any account whose name does not
start with `wtf1132`. Your own account is never touched.

## Files in this package

| File | Role |
|---|---|
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
/Applications/1132.WTF.app/Contents/MacOS/1132.WTF browser "https://zoom.us/j/1234567890"
/Applications/1132.WTF.app/Contents/MacOS/1132.WTF restore
```

With no arguments it shows the chooser. With `--background` it runs a level 1
reset silently, which is what the login item uses.

## When it does not work

Run **Status** first, then read this:

| Symptom | What is really happening | What helps |
|---|---|---|
| Zoom still opens with your old name | Keychain / iCloud Keychain signed you back in, or Zoom used your **Mac login name** as the guest default | Run Fix now, type a different name, do not sign into the blocked Zoom account. If iCloud Keychain is on, delete Zoom from Keychain Access |
| "Join new room?" after typing a meeting ID | Meeting history was still on disk (helpers or Group Containers survived an older wipe) | This build wipes those. Re-download, run Fix now, do not open Zoom from the Dock first |
| Deleting wtf1132 accounts changed nothing | Those accounts only matter if you **switch** to them. Staying on this Mac login keeps the same identity | Use Fix now on this login, or Deep fix and actually switch users |
| 1132 returns immediately, on the throwaway account too | The block is on your **Zoom account**, server side | A different Zoom account, or join as a guest from the browser |
| Level 1 does nothing but level 2 works | Zoom is fingerprinting something outside its data folder | Keep using level 2, or use the browser |
| No account on this Mac can join, but your phone can | The block is on your **IP address** | A VPN, or a phone hotspot |
| "Zoom is not installed on this Mac" | The client is somewhere Spotlight cannot see | Reinstall Zoom, or just use level 3 |
| Zoom will not quit | Another app is holding a Zoom window | Quit Zoom yourself, then run level 1 again |

No app running on your Mac can un-ban a server-side Zoom account. When that is
what is happening, Status says so rather than pretending otherwise.

## Logs

```
~/Library/Logs/1132.WTF
```

One `engine_<timestamp>.log` per run.
