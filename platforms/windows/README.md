# 1132.WTF for Windows

Zoom error 1132, fixed.

Works on Windows 10 and 11 with the PowerShell that already ships with
Windows. Nothing to install, no runtime to download.

## Start here

Double-click **`1132.WTF.vbs`**. The app window opens.

![the app](../../brand/out/wordmark.png)

Then work down the buttons in order. Stop as soon as you get back into the
meeting.

| Button | What it does | Admin needed |
|---|---|---|
| **FIX NOW** | Erases the Zoom client identity on this PC and relaunches Zoom with an empty profile | no |
| **DEEP FIX** | Creates a temporary standard Windows user and runs Zoom as that user | yes |
| **JOIN IN BROWSER** | Opens a fresh private browser window so you can join without the client at all | no |

If you would rather not use the window, every action has a one-click file:

| File | Same as |
|---|---|
| `FIX_NOW.bat` | FIX NOW |
| `DEEP_FIX.bat` | DEEP FIX |
| `JOIN_IN_BROWSER.bat` | JOIN IN BROWSER |
| `STATUS.bat` | Status |
| `UNDO_LAST_FIX.bat` | Undo last fix |
| `INSTALL_AUTOSTART.bat` | Run a level 1 reset at every logon |
| `REMOVE_AUTOSTART.bat` | Stop running at logon |
| `OPEN_LOGS.bat` | Open the log folder |
| `TROUBLESHOOT_VISIBLE.bat` | FIX NOW in a console that stays open |
| `CREATE_DESKTOP_SHORTCUT.bat` | Branded desktop shortcut |

## What it changes on your PC

`FIX NOW` moves these into a timestamped backup, then deletes the originals:

```
%APPDATA%\Zoom\data
%APPDATA%\Zoom\logs
%LOCALAPPDATA%\Zoom\data
HKCU\Software\Zoom      (exported to a .reg file first)
```

Nothing is deleted without a backup, and **Undo last fix** puts the most
recent one back. Backups live in `%ProgramData%\1132.WTF\backups`.

`DEEP FIX` additionally creates one temporary user account named
`wtf1132_a`, `wtf1132_b`, or `wtf1132_c`, rotating through the three. Before
reusing a slot it deletes the oldest one, so at most two exist at a time.
Those accounts:

- are **standard users, not administrators**, because Zoom does not need admin
- get a **random 24-character password on every run** that is never saved to
  disk and never written into a log
- can only ever be deleted by this rotation, because the engine refuses to
  touch any account whose name does not start with `wtf1132_`

To remove them by hand at any time: Settings → Accounts → Other users.

## Files in this package

| File | Role |
|---|---|
| `1132.WTF.vbs` | quiet launcher, opens the app window with no console flash |
| `1132.WTF.bat` | dispatcher, also the command-line entry point |
| `1132WTF_APP.ps1` | the app window |
| `1132WTF_ENGINE.ps1` | the engine that does the work |
| `assets\1132.WTF.ico` | app icon |

Keep them in the same folder. The launchers look for each other by relative
path.

## Command line

```bat
1132.WTF.bat /fix
1132.WTF.bat /deep
1132.WTF.bat /browser "https://zoom.us/j/1234567890"
1132.WTF.bat /status
1132.WTF.bat /restore
1132.WTF.bat /autostart-on
1132.WTF.bat /autostart-off
1132.WTF.bat /logs
1132.WTF.bat /visible
```

Or drive the engine directly:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File 1132WTF_ENGINE.ps1 -Action status
```

## When it does not work

1132 is not always on your machine. Run `STATUS.bat` first, then read this:

| Symptom | What is really happening | What helps |
|---|---|---|
| 1132 returns instantly after FIX NOW, on every account | The block is on your **Zoom account**, server side | Sign in with a different Zoom account, or join as a guest from the browser |
| DEEP FIX works but plain FIX NOW does not | Zoom is fingerprinting something outside its data folder | Keep using DEEP FIX, or use the browser |
| Nothing on this PC works, but your phone can join | The block is on your **IP address** | A VPN, or a different network such as a phone hotspot |
| "Zoom was not found" | The client is not installed where the engine looks | Install Zoom, or just use JOIN IN BROWSER |
| Nothing happens on double-click | Windows blocked the script because it came from a zip | Right-click the zip → Properties → Unblock, then extract again |

An app running on your laptop cannot un-ban a server-side Zoom account. When
that is what is happening, the status output says so instead of pretending.

## Logs

```
%ProgramData%\1132.WTF\logs
```

One `engine_<timestamp>.log` per run, with the same `[LEVEL] message` lines
the app window shows.
