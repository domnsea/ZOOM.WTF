# The 1132.WTF engine

Every platform package implements the same contract. This document is the
reference the five implementations are written against.

## What Zoom error 1132 actually is

Zoom shows `1132` when the meeting host, or Zoom itself, has blocked you.
The block is not attached to your name — it is attached to a set of
identifiers Zoom can see:

| Identifier | Where it lives | Who can reset it |
|---|---|---|
| Zoom account | server side | you, by using a different account |
| Client device id / local profile | Zoom's own data directory | 1132.WTF |
| OS user account fingerprint | your operating system user | 1132.WTF (desktop, deep mode) |
| Public IP | your network | a VPN or a different network |

1132.WTF resets everything in the two middle rows, which is the part that is
actually on your machine, and tells you plainly when the remaining rows are
what is still blocking you. Nothing else can be honest about this: an app
running on your laptop cannot un-ban a server-side account.

## Levels

The engine exposes three escalating levels. Each platform implements the
levels it physically can.

### Level 1 — `fix` (reset)

Quit Zoom, back up and erase Zoom's local identity (data dir, preferences,
caches, cookies, saved state), then relaunch Zoom against a brand new empty
profile directory. No administrator rights required. This clears the client
device id, which is what 1132 keys off most often.

### Level 2 — `deep-fix` (rotate)

Create a throwaway operating-system user, then launch Zoom as that user with
its own profile directory. Zoom sees a completely different machine-local
identity. The engine keeps three rotation slots and destroys the oldest slot
before reusing it, so no more than two throwaway users exist at a time.

Rotation order, where the slot about to run is `n`:

| Launching slot | Slot destroyed first |
|---|---|
| 1 | 2 |
| 2 | 3 |
| 3 | 1 |

Requires administrator / root. Desktop only — iOS and Android do not let one
app create operating-system users.

On macOS the throwaway user is hidden, Zoom is opened on the **current
desktop** (no profile switch, no password to write down), and the user is
deleted automatically when that Zoom instance quits.

### Level 3 — `browser` (bypass)

Join the meeting in a fresh private browser session instead of the Zoom
client. This skips the native client fingerprint entirely and is the fastest
thing that works when levels 1 and 2 do not. Available on all five platforms,
because every platform can open a URL.

## Command surface

Desktop packages (Windows, macOS, Linux) expose these verbs. The GUI entry
points on each platform are thin wrappers that call them.

| Verb | Effect |
|---|---|
| `status` | Report detected Zoom, current slot, last run, backup count |
| `fix` | Level 1, then launch Zoom |
| `deep-fix` | Level 2, then launch Zoom as the throwaway user |
| `browser [url]` | Level 3, open a private browser session |
| `restore` | Put back the most recent identity backup |
| `autostart on\|off` | Install or remove the login item |
| `logs` | Open, or print the path of, the log directory |

Mobile packages expose levels 1-partial and 3 through their UI, because the
sandbox forbids the rest. See [MOBILE.md](MOBILE.md) for exactly which parts
of the contract iOS and Android can and cannot honour, and why.

## Where Zoom keeps identity, per platform

The reset step targets these paths. Everything is copied into a timestamped
backup directory before deletion, and `restore` reverses it.

**Windows**

```
%APPDATA%\Zoom\data
%APPDATA%\Zoom\logs
HKCU\Software\Zoom
```

**macOS**

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
~/Library/LaunchAgents/*zoom*
~/.zoomus
keychain: every item labeled or serviced zoom.us / us.zoom.xos / Zoom
          (loop-deleted; one delete-generic-password call is not enough)
```

After the wipe, macOS launches Zoom as a **new instance** (`open -n`) against
an empty `--data=` profile. `open -a` without `-n` reuses the running app and
its old name, rooms, and signed-in account.

**Linux**

```
~/.zoom
~/.config/zoomus.conf
~/.cache/zoom
```

## Safety rules every implementation follows

1. **Back up before deleting.** Every destructive step writes a timestamped
   backup first, and `restore` is always available.
2. **Never touch the user's own account.** Throwaway users are created with
   generated names in a reserved prefix and are only ever deleted by slot
   rotation.
3. **Throwaway users are not administrators.** Zoom does not need admin, so
   the rotation accounts are created as standard users.
4. **Throwaway passwords are random per run** and are never written to disk
   or into logs.
5. **Single instance.** A lock directory prevents two runs racing on the same
   profile.
6. **Everything is logged**, with a stable `[LEVEL] message` line format, to a
   per-platform log directory.
7. **No silent failure.** A failed run surfaces a native dialog on GUI entry
   points and a non-zero exit code on CLI ones.
