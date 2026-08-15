# What the phone apps can and cannot do

The desktop versions of 1132.WTF can reach into Zoom's data directory and can
create operating-system users. The phone versions cannot do either, and no
amount of engineering changes that. This document is the honest accounting of
where each level stands on iOS and Android, and why.

It exists because the tempting thing to build is a mobile app that *looks* like
it is fixing something. That would waste your time in the exact moment you have
none, which is while a meeting is happening without you.

## The three levels, per platform

| Level | Windows | macOS | Linux | Android | iOS |
|---|---|---|---|---|---|
| 1 Reset Zoom's local identity | automatic | automatic | automatic | guided | guided |
| 2 Throwaway operating-system user | automatic | semi-automatic | automatic | guided | **impossible** |
| 3 Fresh browser session | automatic | automatic | automatic | **automatic** | **automatic** |

"Guided" means the app cannot do it, so it takes you to the one screen that can
and tells you exactly which taps to make. "Impossible" means the platform has no
such concept.

## Level 1: why an app cannot clear Zoom's data

Both mobile platforms give every app a private storage area that no other app
can read or write. That is the single most important security property either
platform has, and it is the reason a malicious app cannot rifle through your
banking app. It also means 1132.WTF cannot delete Zoom's device registration for
you.

**Android** has one exception, `root`, which most phones do not have and which
1132.WTF will not ask you to obtain. Instead the app fires an intent at
`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` for `us.zoom.videomeetings`,
which lands you directly on Zoom's own page in Settings. From there it is Force
stop, Storage, Clear storage. Three taps, and the app tells you which three.

**iOS** has no exception at all, and does not even allow a deep link into
another app's settings page. `UIApplication.openSettingsURLString` opens *this*
app's settings and nothing else. So the iOS card spells out the route through
General, iPhone Storage, Zoom, Delete App, and is explicit that Offload App is
not enough, because offloading deliberately preserves the documents and data
that have to go.

## Level 2: multiple users on Android, nothing on iOS

**Android** supports multiple users. A second user has separate app storage, a
separate Zoom install, and a separate device registration, which makes it a real
equivalent of the throwaway desktop account. The app checks
`UserManager.supportsMultipleUsers()` and only offers it when the device allows
it, because some manufacturers disable it. Creating the user still has to happen
in Settings, so the app deep-links there.

**iOS has no second user profile.** Not restricted, not gated behind a
setting — the concept does not exist on iPhone. The iOS app says exactly that,
and points at level 3 instead. This is the one place where being useful means
admitting there is nothing to offer.

## Level 3: fully implemented, and the one that usually works

This is where the mobile apps are strongest, and it is not a consolation prize.

Zoom's web client runs in a web view. It carries **none** of the native app's
device identity, which is the thing error 1132 is usually attached to. Both apps
embed it in a web view whose storage they own outright, so they can genuinely
guarantee a clean session rather than asking you to trust that a browser behaved.

**Android** uses a `WebView` and clears `CookieManager`, `WebStorage`, cache,
history, and form data before every load and again on exit.

**iOS** uses a `WKWebView` built on a **non-persistent `WKWebsiteDataStore`**,
so the session exists in memory only and cannot outlive the screen. "Wipe and
reload" discards the entire store rather than merely reloading the page.

Both request camera and microphone only for this screen, so a meeting joined
this way is a real meeting you can speak in, not a read-only view.

## What neither platform can fix, and neither claims to

If the block is on your **Zoom account** or your **IP address**, nothing
installed on the phone matters. Both apps say so in the troubleshooting card, in
plain words, with what to do instead:

- Account-level block, so make a new account or join as a guest without signing
  in. The apps generate a plus-address for the new account, because most mail
  providers deliver it to the same inbox while Zoom treats it as a different
  address.
- IP-level block, so switch between Wi-Fi and mobile data.
- A host who removed you by name, so join with a different display name. The
  apps generate one and copy it to the clipboard.

## Shared logic, tested against both implementations

Meeting link parsing is identical on both platforms and is the fiddliest code in
either app: it has to cope with a bare id, an id typed with spaces or dashes, a
regional `us02web.zoom.us` link, a `zoommtg://` deep link, and a link carrying a
password.

Both implementations are covered by the same table of cases:

```bash
tests/test_android_logic.sh   # plain JDK, no emulator or SDK needed
tests/test_ios_logic.sh       # open-source Swift toolchain, no Mac needed
```

Keeping the case lists identical is what stops the two platforms quietly
disagreeing about what a meeting link means.
