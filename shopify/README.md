# 1132.WTF on ballroom-shopify-featured-links-v6

This folder updates the live **1132.WTF** page (`/pages/zoom-wtf`) so it sells **Mac, Windows, Linux, iOS, and Android** — **$10 each** — with Shopify auto-emailing the matching digital zip after payment.

It is built for the theme export:

`theme_export__ballroom-wtf-ballroom-shopify-featured-links-v6__15AUG2026-0328pm`

The live page currently only offers Windows, Mac, and Linux. All five products already exist in the Ballroom.WTF catalog at $10 and do not require shipping.

## Products already on the shop

| Platform | Product | Handle | Variant ID | Price |
|---|---|---|---|---|
| Mac | 1132 MAC WORKAROUND | `1132-mac-workaround` | `52818503008532` | $10 |
| Windows | 1132 WINDOWS WORKAROUND | `1132-windows-workaround` | `52818503139604` | $10 |
| Linux | 1132 LINUX WORKAROUND | `1132-linux-workaround` | `52939951964436` | $10 |
| iOS | 1132 iOS(iPhone) Workaround | `digital-product` | `53566816846100` | $10 |
| Android | 1132 ANDROID WORKAROUND | `1132-android-workaround` | `53656022221076` | $10 |

## 1. Patch the theme, then upload it

Shopify only goes live when you **upload the theme ZIP**. Editing this GitHub repo does not change ballroom.wtf by itself.

Unzip the theme export, then:

```bash
python3 shopify/apply_five_platforms.py /path/to/theme_export__ballroom-wtf-ballroom-shopify-featured-links-v6__15AUG2026-0328pm
```

That rewrites the inlined 1132.WTF page, the sitewide buy modal, and homepage copy from “Windows · Mac · Linux” to all five platforms.

Then:

1. Zip the patched theme folder.
2. Shopify Admin → **Online Store → Themes → Add theme → Upload zip**.
3. Preview, then **Publish**.

### Or copy the Liquid drop-ins

`shopify/theme-patch/` is the same page and modal as snippets:

| Copy this | Into the theme as |
|---|---|
| `snippets/zoom-wtf-platform-data.liquid` | `snippets/zoom-wtf-platform-data.liquid` |
| `snippets/zoom-wtf-platform-buttons.liquid` | `snippets/zoom-wtf-platform-buttons.liquid` |
| `snippets/zoom-wtf-buy-js.liquid` | `snippets/zoom-wtf-buy-js.liquid` |
| `snippets/zoom-wtf-page.liquid` | `snippets/zoom-wtf-page.liquid` |
| `snippets/zoom-wtf-modal.liquid` | `snippets/zoom-wtf-modal.liquid` |
| `templates/page.zoom-wtf.liquid` | `templates/page.zoom-wtf.liquid` |
| `sections/zoom-wtf-page.liquid` | `sections/zoom-wtf-page.liquid` |

In `layout/theme.liquid`, keep `{% render 'zoom-wtf-modal' %}` before `</body>`. Assign the **zoom-wtf** template to the 1132.WTF page.

## 2. Attach the zips so Shopify emails them

Checkout already collects the buyer’s email and sends them to Shopify checkout. Auto-delivery still needs a file on each product.

Shopify Admin → **Settings → Apps → Digital downloads** (Shopify’s free Digital Downloads app). If it is not installed, install it.

Then attach one zip per product:

| Product | File in this repo |
|---|---|
| 1132 MAC WORKAROUND | `dist/1132-FRESH-macos.zip` |
| 1132 WINDOWS WORKAROUND | `dist/1132.WTF-windows-1.0.0.zip` |
| 1132 LINUX WORKAROUND | `dist/1132.WTF-linux-1.0.0.zip` |
| 1132 iOS(iPhone) Workaround | `dist/1132.WTF-ios-1.0.0.zip` |
| 1132 ANDROID WORKAROUND | `dist/1132.WTF-android-1.0.0.zip` |

Confirm each product is **$10.00**, **Digital** / **This is a physical product** is **off**, and inventory is not blocking checkout.

After payment, Shopify emails the download link to the address entered on the 1132.WTF page (that same address is passed into checkout).

## 3. Page SEO in Shopify Admin

Online Store → Pages → the 1132.WTF page (`zoom-wtf`):

- **Title:** `1132.WTF / ZOOM.WTF — Mac, Windows, Linux, iOS, Android`
- **Description:** `Get 1132.WTF for Mac, Windows, Linux, iOS, or Android — $10 each. Shopify emails the installer automatically after payment.`

Leave the page body empty so the theme template supplies the five-platform form. If the body still says “Windows, Mac, or Linux”, delete that HTML.

## What the buyer sees

1. Open `/pages/zoom-wtf`.
2. Enter email.
3. Tap **Mac**, **Windows**, **Linux**, **iOS**, or **Android** — each $10, labeled Auto-email.
4. Pay.
5. Shopify emails the zip for that platform.
