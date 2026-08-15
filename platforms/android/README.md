# 1132.WTF for Android

Zoom error 1132, fixed.

Runs on Android 5.0 and newer. No third-party libraries at all — not even
AndroidX — so the APK is under 200 KB and builds offline once the SDK is in
place.

## How to use

Open `START_HERE.txt`. Short version:

STEP 1 - Open the **`.apk`** on your phone. Allow install.

STEP 2 - Open **1132.WTF**

LAUNCH - Do **STEP 1 - Clear Zoom** on the screen. Then join as a guest.

If that fails: **STEP 2 - New phone user**. If that fails: **STEP 3** and tap **LAUNCH**.

## Install the built APK

If you have the prebuilt APK from the release package, copy it to the phone and
open it. Android will ask you to allow installing from that source, because it
did not come from the Play Store.

With a cable and developer mode on:

```bash
adb install -r 1132.WTF-1.0.0-release.apk
```

## Build it yourself

You need the Android SDK (platform 34, build-tools 34.0.0) and a JDK 17 or
newer. Both come with Android Studio.

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
./build-apk.sh
```

That produces a **signed, installable** APK. On the first run it generates a
signing key and writes `keystore.properties`. Keep both files: Android only
accepts an update to an installed app if it is signed with the same key.
Neither file is ever committed.

For a quick unsigned-for-development build:

```bash
./build-apk.sh --debug
```

Or open the `platforms/android` folder in Android Studio and press Run.

## What it can and cannot do

Android sandboxing, not ambition, decides this. The app is organised around what
is actually possible, and says so plainly where something is not.

| Level | On Android | Why |
|---|---|---|
| **1 Reset Zoom** | Guided, not automatic | No app may clear another app's data without root. The app opens Zoom's own system page with the steps spelled out. |
| **2 Throwaway user** | Guided | Android *does* have multiple users, which is the real equivalent of a throwaway desktop account. The app deep-links to that settings screen. |
| **3 Clean room join** | **Fully implemented** | The app owns its own WebView cookie jar, so it can genuinely erase the session itself. |

### The clean room is the real feature

Level 3 loads Zoom's web client in a WebView that this app controls. Before
every load it empties the cookie jar, DOM storage, cache, history, and form
data, and it does the same again on exit. "Wipe and reload" repeats it on
demand.

That matters because the web client carries none of the Zoom app's device
identity, which is what error 1132 is usually attached to. It is the one level
the app can carry out entirely by itself, with no steps for you to follow.

Camera and microphone are requested only for this screen, and only granted to
the web view once you have granted them to the app, so you can actually talk in
a meeting joined this way.

### Why level 2 is worth doing on Android

A second Android user is genuinely separate: its own app storage, its own Zoom
installation, its own device registration. It is the closest thing on a phone to
the throwaway operating-system account the desktop versions create, and it works
for the same reason.

Not every device allows extra users. Where `UserManager.supportsMultipleUsers()`
says no, the card greys out and explains that it is the manufacturer's
restriction rather than pretending the button will help.

## Project layout

```
app/src/main/java/wtf/fix1132/android/
  MainActivity.java        the screen
  CleanRoomActivity.java   level 3, the wiped WebView session
  Brand.java               palette and view builders
  ZoomProbe.java           what can be told about Zoom on this device
  MeetingLink.java         turns a pasted link or ID into a web client URL
  Identity.java            throwaway display names and email aliases
app/src/main/res/          icons, colours, strings, theme
build-apk.sh               one-command signed build
```

The interface is built in code rather than layout XML, which is what keeps the
dependency list empty.

## Why the app declares a `<queries>` block

From Android 11, an app cannot see which other apps are installed unless it says
which ones it cares about. Without the `<queries>` entry for
`us.zoom.videomeetings`, the very first thing the app reports — whether Zoom is
installed — would always say no. That is the only reason it is there.

## Tests

The Android-free logic is tested on a plain JDK, with no emulator or SDK needed:

```bash
tests/test_android_logic.sh
```

That covers meeting link parsing and the identity generator, which is the part
most likely to break quietly. The same cases run against the iOS implementation
in `tests/test_ios_logic.sh`, so the two platforms cannot drift apart.

## When it does not work

| Symptom | What is really happening | What helps |
|---|---|---|
| 1132 returns instantly, even in a fresh profile | The block is on your **Zoom account**, server side | A new Zoom account, or join as a guest without signing in |
| Nothing on this phone works, but a laptop can join | The block is on your **IP address** | Mobile data instead of Wi-Fi, or the other way round |
| The host removed you by name | A manual, name-based removal | Join with a different display name, which the app generates |
| The clean room loads but the meeting will not start | Zoom's web client sometimes refuses an unusual browser build | Use "Open in my browser instead" |

No app on your phone can undo a block that lives on Zoom's servers. When that is
what is happening, the app says so rather than looking busy.
