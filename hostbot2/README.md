# HOSTBOT2 → ZOOM DIRECTORY

The live page is [ballroom.wtf/pages/zoom-directory](https://ballroom.wtf/pages/zoom-directory). It currently only says “DIRECTORY OF ZOOM ROOMS”. This folder is the feed HOSTBOT2 should publish into that page.

HOSTBOT2 itself is not in this repo (it lived as a local file, `HOSTBOT2.html`). Drop this matcher next to it.

## What to match

1. **The key already has the room names.** Do not invent rooms from posts. The directory lists every room on the key.
2. **Posts usually name the room as a website.** `ballroom.wtf` in a Telegram/Discord post is Ballroom. That clue wins over a name mention.
3. Other clues, in order: room website / domain, room name used as a domain, known meeting ID, aliases, room name as a phrase.
4. The Shopify page **refreshes every 5 minutes**.

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
  --out /path/to/theme/assets/zoom-directory.json
```

`--hostbot2` looks for `key.json` / `key.txt` / `KEY.txt` / `rooms.json` and `posts.json` / `feed.json` / `telegram.json`.

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

JSON array of `{ "text": "...", "ts": "...", "source": "telegram" }` or a Telegram-style export. A post with a Zoom link plus `ballroom.wtf` updates Ballroom’s join URL. A Zoom link with no key match goes to `unmatched` and is **not** shown on the public page.

## Shopify page

See `shopify/README.md`. The directory template fetches `assets/zoom-directory.json` every 5 minutes (`cache: 'no-store'` plus a timestamp query).
