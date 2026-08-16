# HOSTBOT2 → ZOOM DIRECTORY

The live page is [ballroom.wtf/pages/zoom-directory](https://ballroom.wtf/pages/zoom-directory). It currently only says “DIRECTORY OF ZOOM ROOMS”. This folder is the feed HOSTBOT2 should publish into that page.

HOSTBOT2 itself is not in this repo (it lived as a local file, `HOSTBOT2.html`). Drop this matcher next to it.

## What to match

1. **The key already has the room names.** Do not invent rooms from posts. The directory lists every room on the key.
2. **Posts usually name the room as a website.** `ballroom.wtf` in a Telegram/Discord post is Ballroom. That clue wins over a name mention.
3. Other clues, in order: room website / domain, room name used as a domain, known meeting ID, aliases, room name as a phrase.
4. **2060220206 is not Ballroom.** That ID was used one time. Do not show it as Ballroom.
5. **The 973 number being promoted is Ballroom.** Meeting IDs that start with `973` map to Ballroom.
6. **ROOMS.txt remembers names.** One line per room: `NUMBER    NAME`. Unknown numbers are listed without a name — add the name next to the number and save.
7. The Shopify page **refreshes every 5 minutes**.

## ROOMS.txt

```
# NUMBER    NAME
97312345678    Ballroom
55566677788    Palace
12121212121
```

The last line has no name yet. Type `Circuit` after the number, save, and the directory keeps calling that number Circuit.

Live file: Shopify **Assets → ROOMS.txt**. Same file lives at `shopify/theme-patch/assets/ROOMS.txt` and `hostbot2/ROOMS.txt`.

## Publish a feed

```bash
python3 hostbot2/publish_directory.py \
  --hostbot2 /path/to/HOSTBOT2 \
  --out shopify/theme-patch/assets/zoom-directory.json
```

Or pass the files directly:

```bash
python3 hostbot2/publish_directory.py \
  --key /path/to/HOSTBOT2/key.json \
  --posts /path/to/HOSTBOT2/posts.json \
  --rooms shopify/theme-patch/assets/ROOMS.txt \
  --out /path/to/theme/assets/zoom-directory.json
```

`--hostbot2` looks for `key.json` / `key.txt` / `ROOMS.txt` and `posts.json` / `feed.json` / `telegram.json`.

Copy `zoom-directory.json` into the Shopify theme **Assets**, then upload/publish the theme (same rule as the rest of ballroom.wtf: editing GitHub does not go live). Re-run this whenever HOSTBOT2 sees new posts — at least every 5 minutes.

## Key formats

JSON:

```json
{
  "rooms": [
    { "name": "Ballroom", "website": "https://ballroom.wtf", "aliases": ["BALLROOM"] }
  ]
}
```

Text (one room per line). Name first; website second:

```
Ballroom    ballroom.wtf
Palace      palace.party
```

or `Ballroom | ballroom.wtf | BALLROOM, Ballroom Zoom`.

## Posts

JSON array of `{ "text": "...", "ts": "...", "source": "telegram" }` or a Telegram-style export. A post with a Zoom link plus `ballroom.wtf` updates Ballroom’s join URL. A Zoom link with no name shows on the directory as **NEEDS NAME** — add `NUMBER    NAME` to `ROOMS.txt` and it remembers.

## Shopify page

See `shopify/README.md`. The directory template fetches `assets/zoom-directory.json` every 5 minutes (`cache: 'no-store'` plus a timestamp query).
