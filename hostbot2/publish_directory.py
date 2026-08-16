#!/usr/bin/env python3
"""Build zoom-directory.json from a HOSTBOT2 key + posts.

ROOMS.txt remembers names: NUMBER    NAME
Unknown numbers are written back so you can add a name next to them.

Usage:
  python3 hostbot2/publish_directory.py --hostbot2 /path/to/HOSTBOT2
  python3 hostbot2/publish_directory.py --key key.json --posts posts.json --rooms ROOMS.txt
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from match_rooms import (
    REFRESH_SECONDS,
    build_directory,
    discover_hostbot2_files,
    dump_directory,
    load_maybe,
    parse_rooms_txt,
    write_rooms_txt,
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Publish the ZOOM DIRECTORY feed from HOSTBOT2.")
    parser.add_argument("--hostbot2", type=Path, help="HOSTBOT2 folder (looks for key + posts + ROOMS.txt)")
    parser.add_argument("--key", type=Path, help="Key file (JSON/text). Room names live here.")
    parser.add_argument("--posts", type=Path, help="Posts/feed file from HOSTBOT2")
    parser.add_argument(
        "--rooms",
        type=Path,
        help="ROOMS.txt memory file (NUMBER then NAME). Created/updated with unknown numbers.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("shopify/theme-patch/assets/zoom-directory.json"),
        help="Output JSON for the Shopify directory page",
    )
    args = parser.parse_args(argv)

    key_path = args.key
    posts_path = args.posts
    rooms_path = args.rooms
    if args.hostbot2:
        found = discover_hostbot2_files(args.hostbot2)
        key_path = key_path or found["key"]
        posts_path = posts_path or found["posts"]
        rooms_path = rooms_path or found["rooms_txt"]

    if key_path is None and rooms_path is None:
        parser.error("pass --key, --rooms, or --hostbot2")

    key = load_maybe(key_path) if key_path else []
    posts = load_maybe(posts_path) if posts_path else []
    directory = build_directory(key, posts, rooms_txt=rooms_path)
    dump_directory(directory, args.out)

    if rooms_path is not None:
        extra = [
            room.get("room_number")
            for room in directory["rooms"]
            if room.get("needs_name") and room.get("room_number")
        ]
        extra.extend(item.get("room_number") for item in directory.get("unmatched") or [] if item.get("room_number"))
        named = [
            {"meeting_id": room["room_number"], "name": room["name"]}
            for room in directory["rooms"]
            if room.get("room_number") and room.get("name") and not room.get("needs_name")
        ]
        named.extend(parse_rooms_txt(rooms_path))
        write_rooms_txt(rooms_path, named, extra)

    open_count = sum(1 for room in directory["rooms"] if room["status"] == "open")
    need = sum(1 for room in directory["rooms"] if room.get("needs_name"))
    print(
        f"Wrote {args.out}  rooms={len(directory['rooms'])}  "
        f"open={open_count}  needs_name={need}  unmatched={len(directory['unmatched'])}  "
        f"refresh={REFRESH_SECONDS}s"
    )
    if rooms_path is not None:
        print(f"Remembered names in {rooms_path}")
    if posts_path is None:
        print("No posts file — directory lists key/ROOMS.txt rooms as closed.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
