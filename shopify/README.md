# Header logo, ZOOM DIRECTORY, and 1132.WTF five platforms

Live shop: [ballroom.wtf](https://ballroom.wtf). Shopify only changes when you **upload the theme ZIP**.

This patch:

1. Puts the looping **Ballroom logo video** top-left on every page (`assets/ballroom-header-logo.mp4`).
2. Measures the header banner and pushes every following section down so content is not under it.
3. Adds **ZOOM DIRECTORY** on the top nav line, next to **1132.WTF**, in **white**.
4. Updates `/pages/zoom-wtf` so **Mac, Windows, Linux, iOS, and Android** are each **$10** and **auto-emailed** after payment.

## Replace the logo with your Grok video

Copy your Downloads file over the theme asset, then apply:

```bash
cp "/Users/dustin/Downloads/grok-video-019f7d62-c15f-7552-908b-b6a0e4393ee6.mp4" \
  shopify/theme-patch/assets/ballroom-header-logo.mp4
```

Or drop that same file into Shopify Admin → **Online Store → Themes → Edit code → Assets** as `ballroom-header-logo.mp4` after the theme is uploaded.

## Patch the theme, then upload it

Unzip the current theme export, then:

```bash
python3 shopify/apply_site.py /path/to/theme_export__ballroom-wtf-ballroom-shopify-featured-links-v6__15AUG2026-0328pm
```

That copies the video, injects `{% render 'site-header-chrome' %}` before `</body>`, adds ZOOM DIRECTORY next to 1132.WTF, and rewrites the 1132.WTF page/modal to all five platforms.

Zip the patched theme → Shopify Admin → **Online Store → Themes → Add theme → Upload zip** → Preview → **Publish**.

## 1132.WTF products already on the shop ($10 each)

| Platform | Product | Handle | Variant ID |
|---|---|---|---|
| Mac | 1132 MAC WORKAROUND | `1132-mac-workaround` | `52818503008532` |
| Windows | 1132 WINDOWS WORKAROUND | `1132-windows-workaround` | `52818503139604` |
| Linux | 1132 LINUX WORKAROUND | `1132-linux-workaround` | `52939951964436` |
| iOS | 1132 iOS(iPhone) Workaround | `digital-product` | `53566816846100` |
| Android | 1132 ANDROID WORKAROUND | `1132-android-workaround` | `53656022221076` |

Attach the zips with Shopify’s **Digital Downloads** app so checkout emails the file:

| Product | File |
|---|---|
| Mac | `dist/1132-FRESH-macos.zip` |
| Windows | `dist/1132.WTF-windows-1.0.0.zip` |
| Linux | `dist/1132.WTF-linux-1.0.0.zip` |
| iOS | `dist/1132.WTF-ios-1.0.0.zip` |
| Android | `dist/1132.WTF-android-1.0.0.zip` |

Each product must stay **$10.00** and **not** a physical product. After payment, Shopify emails the zip to the address entered on the 1132.WTF page.

## What visitors see

- Every page: looping logo top-left; page content starts below the header banner.
- Top nav: `1132.WTF` (lime) then `ZOOM DIRECTORY` (white) then the rest of the links.
- `/pages/zoom-wtf`: email field, then Mac / Windows / Linux / iOS / Android — each `$10.00 · Auto-email`.
