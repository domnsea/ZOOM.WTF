#!/usr/bin/env python3
"""Patch a ballroom theme export for:

- looping header logo video (top left, every page)
- ZOOM DIRECTORY next to 1132.WTF (white)
- header-banner offset on every page
- 1132.WTF Mac / Windows / Linux / iOS / Android at $10 auto-email

Usage:
  python3 shopify/apply_site.py /path/to/unzipped-theme
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from apply_five_platforms import apply_five_platforms  # noqa: E402
from apply_header import apply_header  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("theme", type=Path, help="Unzipped theme folder")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    theme_root = args.theme.expanduser().resolve()
    if not theme_root.is_dir():
        print(f"Not a directory: {theme_root}", file=sys.stderr)
        return 2

    header = apply_header(theme_root, dry_run=args.dry_run)
    five = apply_five_platforms(theme_root, dry_run=args.dry_run)

    if header.get("copied"):
        print("Copied " + ", ".join(header["copied"]))
    if header.get("injected"):
        print("Injected {% render 'site-header-chrome' %} into layout/theme.liquid")
    action = "Would update" if args.dry_run else "Updated"
    for rel, n in header.get("changed") or []:
        print(f"{action} header {rel} ({n})")
    if five:
        print(f"{action} 1132.WTF {len(five)} file(s)")
        for path, n in five:
            print(f"  {path} ({n})")
    print("Upload the theme ZIP to Shopify to go live.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
