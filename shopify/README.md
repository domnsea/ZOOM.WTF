# ZOOM DIRECTORY from HOSTBOT2

Live page: [ballroom.wtf/pages/zoom-directory](https://ballroom.wtf/pages/zoom-directory).

Right now that page is only the Shopify body text `DIRECTORY OF ZOOM ROOMS`. This patch turns it into a live list of rooms from **HOSTBOT2**, refreshed every **5 minutes**.

Room identity comes from the HOSTBOT2 **key** (it already has the room names). A post usually names the room as a **website** — `ballroom.wtf` in the post means Ballroom. Website clues beat a stray name mention so rooms do not get mixed up.

**2060220206 is not Ballroom** — that ID was used once. **The 973 number being promoted is Ballroom.**

Shopify only goes live when you **upload the theme ZIP**. Editing this GitHub repo does not change ballroom.wtf by itself.

## 1. Patch the theme, then upload it

Unzip the current theme export, then:

```bash
python3 shopify/apply_directory.py /path/to/theme_export__ballroom-wtf-ballroom-shopify-featured-links-v6__15AUG2026-0328pm
```

That copies:

| Into the theme | Role |
|---|---|
| `snippets/zoom-directory.liquid` | Directory UI + 5-minute refresh |
| `templates/page.zoom-directory.liquid` | Template for `/pages/zoom-directory` |
| `sections/zoom-directory.liquid` | Online Store 2.0 wrapper |
| `assets/zoom-directory.json` | Feed HOSTBOT2 overwrites |
| `assets/ROOMS.txt` | Number → name memory. Add a name next to an unknown number and save. |
| `layout/theme.liquid` | `{% render 'zoom-directory' %}` before `</body>` |

Zip the patched theme → Shopify Admin → **Online Store → Themes → Add theme → Upload zip** → Preview → **Publish**.

Optional: Online Store → Pages → **ZOOM DIRECTORY** (`zoom-directory`) → Theme template → **zoom-directory**. The snippet also self-activates on `/pages/zoom-directory` if you leave the default template.

Leave the page body as-is (or empty). The placeholder line is hidden once the directory mounts.

## 2. Name unknown rooms in ROOMS.txt

If the directory cannot find a room name, the number still shows with **NEEDS NAME**.

Shopify Admin → **Online Store → Themes → … → Edit code → Assets → ROOMS.txt**. Add the name on that line:

```
97312345678    Ballroom
55566677788    Palace
```

Save. The page refreshes every 5 minutes and **remembers** that name for that number.

Do not put `2060220206 Ballroom` — that ID is not Ballroom. The 973 number is Ballroom.

## 3. Keep the feed updated from HOSTBOT2

On the machine that runs HOSTBOT2:

```bash
python3 hostbot2/publish_directory.py \
  --hostbot2 /path/to/HOSTBOT2 \
  --out /path/to/theme/assets/zoom-directory.json
```

The key file already lists room names (and websites). Posts with a Zoom link plus that website update that room. Copy the JSON into the live theme **Assets** (or re-upload the theme) whenever HOSTBOT2 sees new posts. Do this at least every 5 minutes — the page polls on that interval with `cache: 'no-store'`.

Matcher rules and key formats: [hostbot2/README.md](../hostbot2/README.md).

## What visitors see

1. Open `/pages/zoom-directory`.
2. Every key room is listed.
3. OPEN rooms show the current Zoom join link from HOSTBOT2.
4. CLOSED rooms have no live link yet.
5. Numbers without a name show as **NEEDS NAME**. Add `NUMBER    NAME` in `ROOMS.txt` and the page remembers it.
6. The list reloads every 5 minutes, and again when you come back to the tab.
