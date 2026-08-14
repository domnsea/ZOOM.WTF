# 1132.WTF for iOS

Zoom error 1132, fixed.

A complete SwiftUI app for iPhone and iPad, iOS 16 and newer. Open the project
in Xcode and press Run.

## Build it

**This needs a Mac.** iOS apps can only be compiled by Apple's toolchain, which
only exists on macOS. Nothing can be done about that from Windows or Linux, and
any tool that claims otherwise is either renting you a Mac or not really
building an iOS app.

```bash
open 1132WTF.xcodeproj
```

Pick a simulator, press Run. That is all — the project has no dependencies, no
package manager, and nothing to fetch.

To put it on a real iPhone you need an Apple ID in Xcode. A **free** account
works:

1. Select the `1132WTF` target, then Signing & Capabilities
2. Tick *Automatically manage signing* and choose your team
3. Plug in your iPhone, select it, press Run

Free accounts sign apps for seven days, after which you press Run again. That
is Apple's rule for free accounts, not a limitation of this app.

Or from the command line:

```bash
./build-ios.sh                          # check that it compiles
./build-ios.sh --simulator              # build, install, and launch in a simulator
TEAM_ID=ABCDE12345 ./build-ios.sh --device   # archive for a real iPhone
```

## What it can and cannot do

iOS sandboxing, not ambition, decides this. The app is organised around what is
actually possible, and says so plainly where something is not.

| Level | On iOS | Why |
|---|---|---|
| **1 Reset Zoom** | Guided, not automatic | No app may delete another app's data. The app spells out the delete-and-reinstall steps and opens Settings. |
| **2 Throwaway user** | **Not possible** | iOS has no second user profile and no way for an app to create one. The card says exactly that instead of pretending. |
| **3 Clean room join** | **Fully implemented** | The app owns its own web view data store, so it can genuinely throw the session away. |

### The clean room is the real feature

Level 3 runs Zoom's web client inside a `WKWebView` built on a
**non-persistent `WKWebsiteDataStore`**. Cookies and storage live in memory
only and are gone the moment the screen closes. "Wipe and reload" rebuilds the
whole store rather than just reloading the page.

That matters because the web client carries none of the native Zoom app's
device identity, which is what error 1132 is usually attached to. It is the one
level the app can carry out entirely by itself, with nothing to trust and no
steps for you to follow.

Camera and microphone are requested only for this screen, so you can actually
talk in a meeting you joined through it.

## Project layout

```
1132WTF.xcodeproj          Xcode project, with a shared scheme
1132WTF/
  App.swift                entry point
  ContentView.swift        the screen
  CleanRoomView.swift      level 3, the WKWebView clean session
  Theme.swift              palette and reusable views
  ZoomProbe.swift          what can be told about Zoom on this device
  MeetingLink.swift        turns a pasted link or ID into a web client URL
  Identity.swift           throwaway display names and email aliases
  Info.plist               permissions and the Zoom URL scheme query
  Assets.xcassets          app icon, logo, launch colour
build-ios.sh               command line build helper
```

No CocoaPods, no Swift Package Manager, no third-party code.

## Why the app asks for camera and microphone

Both are needed by the clean room web view, because that is how you join a
meeting with video and audio. They are declared with plain-language reasons in
`Info.plist` and are requested by iOS itself, only when the web client asks. If
you decline, the meeting still opens and you can listen.

## Detecting Zoom

`ZoomProbe` asks whether `zoomus://` can be opened, which only works because
that scheme is listed under `LSApplicationQueriesSchemes` in `Info.plist`. That
is the whole of what iOS lets an app learn about its neighbours, so "not
detected" means only that — not necessarily that Zoom is absent.

## When it does not work

| Symptom | What is really happening | What helps |
|---|---|---|
| 1132 returns even after reinstalling Zoom | The block is on your **Zoom account**, server side | A new Zoom account, or join as a guest without signing in |
| Nothing on this iPhone works, but a laptop can join | The block is on your **IP address** | Mobile data instead of Wi-Fi, or the other way round |
| The host removed you by name | A manual, name-based removal | Join with a different display name, which the app generates |
| The clean room loads but the meeting will not start | Zoom's web client sometimes refuses an unusual browser build | Use "Open in Safari instead", in a Private tab |

No app on your iPhone can undo a block that lives on Zoom's servers. When that
is what is happening, the app tells you so rather than looking busy.
