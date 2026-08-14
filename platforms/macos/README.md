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
| **1 Fix now** | Quits Zoom, backs up and erases Zoom's local identity, reopens Zoom | no |
| **2 Deep fix** | Creates a clean throwaway macOS account and hands you its password | yes |
| **3 Join in browser** | Opens a fresh private browser window so you skip the client entirely | no |

### What level 1 erases

Each item is **moved** into a timestamped backup, never deleted outright:

```
~/Library/Application Support/zoom.us
~/Library/Preferences/us.zoom.xos.plist
~/Library/Caches/us.zoom.xos
~/Library/Cookies/us.zoom.xos.binarycookies
~/Library/Saved Application State/us.zoom.xos.savedState
~/Library/HTTPStorages/us.zoom.xos
```

It also clears Zoom's cached preferences out of `cfprefsd`, because macOS will
otherwise write the old values straight back.

Keychain items named `Zoom Safe Meeting Storage`, `zoom.us`, and `Zoom` are
**deleted rather than backed up**, because macOS cannot export a keychain item
without prompting separately for each one. Zoom recreates them the next time
you sign in.

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
