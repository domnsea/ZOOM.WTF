#!/usr/bin/env python3
"""Build zoom-directory.json from a HOSTBOT2 key + posts.

The key already has room names. Posts usually name the room as a website.

Usage:
  python3 hostbot2/publish_directory.py --hostbot2 /path/to/HOSTBOT2
  python3 hostbot2/publish_directory.py --key key.json --posts posts.json --out zoom-directory.json
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
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Publish the ZOOM DIRECTORY feed from HOSTBOT2.")
    parser.add_argument("--hostbot2", type=Path, help="HOSTBOT2 folder (looks for key + posts)")
    parser.add_argument("--key", type=Path, help="Key file (JSON/text). Room names live here.")
    parser.add_argument("--posts", type=Path, help="Posts/feed file from HOSTBOT2")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("shopify/theme-patch/assets/zoom-directory.json"),
        help="Output JSON for the Shopify directory page",
    )
    args = parser.parse_args(argv)

    key_path = args.key
    posts_path = args.posts
    if args.hostbot2:
        found = discover_hostbot2_files(args.hostbot2)
        key_path = key_path or found["key"]
        posts_path = posts_path or found["posts"]
        if key_path is None:
            print(f"No key file found under {args.hostbot2}", file=sys.stderr)
            print("Expected key.json / key.txt with room names (and websites).", file=sys.stderr)
            return 2

    if key_path is None:
        parser.error("pass --key or --hostbot2")

    key = load_maybe(key_path)
    posts = load_maybe(posts_path) if posts_path else []
    directory = build_directory(key, posts)
    dump_directory(directory, args.out)

    open_count = sum(1 for room in directory["rooms"] if room["status"] == "open")
    print(
        f"Wrote {args.out}  rooms={len(directory['rooms'])}  "
        f"open={open_count}  unmatched={len(directory['unmatched'])}  "
        f"refresh={REFRESH_SECONDS}s"
    )
    if posts_path is None:
        print("No posts file — directory lists key rooms as closed.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
