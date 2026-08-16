# 1132.WTF for Linux

Zoom error 1132, fixed.

Plain bash with no dependencies beyond coreutils, so it runs on any
distribution. It handles Zoom installed natively, as a Flatpak, or as a Snap.

## How to use

Open `START_HERE.txt`. Short version:

STEP 1 - Run **`./install.sh`**

STEP 2 - Open **1132.WTF** from your app launcher (or run `1132wtf-gui`)

LAUNCH - Click **STEP 1 - Fix Zoom**. Join. Do not sign in as the old account.

If that fails: **STEP 2 - Deep fix**. If that fails: **STEP 3 - Join in browser**.

For everyone on the machine:

```bash
sudo ./install.sh --system
```

To remove it later, run `./uninstall.sh` with the same flags you installed
with.

## The three levels

| Level | Command | What it does | Root needed |
|---|---|---|---|
| **1** | `1132wtf fix` | Backs up and erases Zoom's local identity, then restarts Zoom | no |
| **2** | `1132wtf deep-fix` | Creates a throwaway system user and runs Zoom as that user | yes |
| **3** | `1132wtf browser` | Opens a fresh private browser window so you skip the client | no |

Start at level 1 and stop as soon as you are back in the meeting.

### What level 1 erases

Each item is **moved** into a timestamped backup, never deleted outright:

```
~/.zoom
~/.config/zoomus.conf
~/.config/zoom
~/.cache/zoom
~/.var/app/us.zoom.Zoom      (Flatpak installs)
~/snap/zoom-client           (Snap installs)
```

`1132wtf restore` puts the most recent backup back. Backups live in
`~/.local/share/1132wtf/backups`.

### What level 2 does

It creates one user from a rotating set of three: `wtf1132a`, `wtf1132b`,
`wtf1132c`. Before reusing a slot it deletes the oldest, so at most two exist
at a time.

Those accounts are created with `--shell /usr/sbin/nologin` and then locked
with `passwd -l`, so they cannot be logged into or used as a way onto the
machine. They exist only for Zoom to run under. The engine refuses to delete
any account whose name does not start with `wtf1132`, so your own account can
never be caught by the rotation.

To run a GUI app as another user, that user needs permission to talk to your
display, so the engine calls `xhost +SI:localuser:<name>` first.

**On Wayland this often does not work**, because Wayland compositors do not
accept connections from another user the way X11 does. The engine detects a
Wayland session and says so rather than failing silently. If level 2 is what
you need, log out and pick an X11 session, or use level 3 instead.

## Files in this package

| File | Role |
|---|---|
| `1132wtf` | the engine and CLI |
| `1132wtf-gui` | graphical front end, uses zenity, kdialog, or yad |
| `1132wtf.desktop` | launcher entry, with right-click actions for each level |
| `install.sh` / `uninstall.sh` | freedesktop-compliant install and removal |
| `icons/hicolor/...` | icon theme files, 16px through 512px plus SVG |

The GUI picks up whichever dialog tool your desktop already has. With none of
them it falls back to a numbered menu in the terminal, and if there is no
terminal either it just runs a level 1 fix.

## Command line

```bash
1132wtf status                                    # what is on this machine
1132wtf fix                                       # level 1
1132wtf deep-fix                                  # level 2
1132wtf browser "https://zoom.us/j/1234567890"    # level 3
1132wtf restore                                   # undo the last fix
1132wtf autostart-on                              # reset at every login
1132wtf autostart-off
1132wtf logs                                      # print the log directory
1132wtf help
```

Useful environment variables:

| Variable | Effect |
|---|---|
| `WTF1132_ZOOM_BIN` | Path to the Zoom launcher, skipping detection |
| `WTF1132_NO_LAUNCH=1` | Reset without starting Zoom afterwards |
| `WTF1132_ASSUME_YES=1` | Skip interactive confirmations, for scripting |
| `NO_COLOR=1` | Plain output with no colour codes |

## When it does not work

Run `1132wtf status` first, then read this:

| Symptom | What is really happening | What helps |
|---|---|---|
| 1132 returns instantly, even as the throwaway user | The block is on your **Zoom account**, server side | A different Zoom account, or join as a guest in the browser |
| Level 2 says Wayland and Zoom never appears | Wayland will not let another user draw on your session | Use an X11 session, or use level 3 |
| Nothing on this machine works, but your phone can join | The block is on your **IP address** | A VPN, or a phone hotspot |
| "Zoom is not installed" but it is | Installed somewhere unusual | Set `WTF1132_ZOOM_BIN=/path/to/zoom` |
| Level 2 fails with a sudo error | No terminal for the password prompt | Run `1132wtf deep-fix` from a terminal |

No program running on your machine can un-ban a server-side Zoom account. When
that is what is happening, `status` says so rather than pretending otherwise.

## Logs

```
~/.local/share/1132wtf/logs
```

One `engine_<timestamp>_<pid>.log` per run.

## Tests

The engine has an end-to-end test suite that runs against a throwaway `HOME`
and a stub Zoom binary, so it never touches a real install and never needs
root:

```bash
tests/test_linux_engine.sh
```
