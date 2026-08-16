#!/usr/bin/env python3
"""Patch a ballroom-shopify-featured-links-v6 theme so 1132.WTF sells
Mac, Windows, Linux, iOS, and Android at $10 with auto-email checkout.

Usage:
  python3 shopify/apply_five_platforms.py /path/to/unzipped-theme
  python3 shopify/apply_five_platforms.py theme_export__ballroom-wtf-ballroom-shopify-featured-links-v6__15AUG2026-0328pm
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

MAC_VID = "52818503008532"
WIN_VID = "52818503139604"
LINUX_VID = "52939951964436"
IOS_VID = "53566816846100"
ANDROID_VID = "53656022221076"

SKIP_DIRS = {".git", "node_modules", ".theme-check"}
TEXT_SUFFIXES = {".liquid", ".json", ".js", ".css", ".html", ".md"}


def iter_theme_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        yield path


def buttons(class_prefix: str) -> str:
    rows = []
    for platform, vid, extra in (
        ("Mac", MAC_VID, "mac"),
        ("Windows", WIN_VID, "win"),
        ("Linux", LINUX_VID, "linux"),
        ("iOS", IOS_VID, "ios"),
        ("Android", ANDROID_VID, "android"),
    ):
        rows.append(
            f'          <button type="submit" class="{class_prefix}__choice {class_prefix}__choice--{extra}" '
            f'data-zoom-platform="{platform}" data-zoom-vid="{vid}">\n'
            f'            <span class="{class_prefix}__choice-label">{platform}</span>\n'
            f'            <span class="{class_prefix}__choice-sub">$10.00 · Auto-email</span>\n'
            f"          </button>"
        )
    return "\n".join(rows)


PAGE_BUTTONS_OLD = """          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Windows" data-zoom-vid="52818503139604">
            <span class="zoom-wtf-page__choice-label">Windows</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>
          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Mac" data-zoom-vid="52818503008532">
            <span class="zoom-wtf-page__choice-label">Mac</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>
          <button type="submit" class="zoom-wtf-page__choice" data-zoom-platform="Linux" data-zoom-vid="52939951964436">
            <span class="zoom-wtf-page__choice-label">Linux</span>
            <span class="zoom-wtf-page__choice-sub">$10.00 · Auto-email</span>
          </button>"""

MODAL_BUTTONS_OLD = """        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Windows" data-zoom-vid="52818503139604">
          <span class="zoom-wtf-modal__choice-label">Windows</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>
        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Mac" data-zoom-vid="52818503008532">
          <span class="zoom-wtf-modal__choice-label">Mac</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>
        <button type="submit" class="zoom-wtf-modal__choice" data-zoom-platform="Linux" data-zoom-vid="52939951964436">
          <span class="zoom-wtf-modal__choice-label">Linux</span>
          <span class="zoom-wtf-modal__choice-sub">$10.00 · Auto-email</span>
        </button>"""

HOVER_CSS = """    .zoom-wtf-modal__choice--mac:hover { border-color: #7ec94a; }
    .zoom-wtf-modal__choice--win:hover { border-color: #3d95ce; }
    .zoom-wtf-modal__choice--linux:hover { border-color: #e95420; }
    .zoom-wtf-modal__choice--ios:hover { border-color: #7d7d7d; }
    .zoom-wtf-modal__choice--android:hover { border-color: #3ddc84; }
"""

REPLACEMENTS = [
    (
        'Enter your email, pick <strong>Windows</strong>, <strong>Mac</strong>, or <strong>Linux</strong>, pay $10.00. Shopify emails the correct installer automatically after payment.',
        'Enter your email, pick <strong>Mac</strong>, <strong>Windows</strong>, <strong>Linux</strong>, <strong>iOS</strong>, or <strong>Android</strong>, pay $10.00. Shopify emails the correct installer automatically after payment.',
    ),
    (
        "After you pay, the Windows, Mac, or Linux zip is sent automatically to this email. Use the same address at checkout.",
        "After you pay, the Mac, Windows, Linux, iOS, or Android zip is sent automatically to this email. Use the same address at checkout.",
    ),
    (
        "Enter email, pick Windows, Mac, or Linux, pay. The correct installer is emailed automatically after payment.",
        "Enter email, pick Mac, Windows, Linux, iOS, or Android, pay. The correct installer is emailed automatically after payment.",
    ),
    (
        "Windows · Mac · Linux Zoom workaround",
        "Mac · Windows · Linux · iOS · Android",
    ),
    (
        "Buy 1132.WTF for Windows, Mac, or Linux",
        "Buy 1132.WTF for Mac, Windows, Linux, iOS, or Android",
    ),
    (
        "1132.WTF / ZOOM.WTF — Mac &amp; Windows Zoom Workaround",
        "1132.WTF / ZOOM.WTF — Mac, Windows, Linux, iOS, Android",
    ),
    (
        "1132.WTF / ZOOM.WTF — Mac & Windows Zoom Workaround",
        "1132.WTF / ZOOM.WTF — Mac, Windows, Linux, iOS, Android",
    ),
    (
        "Get 1132.WTF (ZOOM.WTF) for Mac or Windows — Ballroom.WTF’s guided Zoom workaround. Paid download from the official ballroom.wtf shop.",
        "Get 1132.WTF for Mac, Windows, Linux, iOS, or Android — $10 each. Shopify emails the installer automatically after payment.",
    ),
    (
        ".zoom-wtf-page__choices { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; margin-top: 8px; }",
        ".zoom-wtf-page__choices { display: grid; grid-template-columns: repeat(auto-fit, minmax(128px, 1fr)); gap: 12px; margin-top: 8px; }",
    ),
    (
        ".zoom-wtf-modal__choices { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }",
        ".zoom-wtf-modal__choices { display: grid; grid-template-columns: repeat(auto-fit, minmax(110px, 1fr)); gap: 10px; }",
    ),
    (
        ".zoom-wtf-modal__panel { position: relative; width: min(100%, 520px);",
        ".zoom-wtf-modal__panel { position: relative; width: min(100%, 640px);",
    ),
    (
        '      data-linux-vid="52939951964436"',
        '      data-linux-vid="52939951964436"\n      data-ios-vid="53566816846100"\n      data-android-vid="53656022221076"',
    ),
    (
        PAGE_BUTTONS_OLD,
        buttons("zoom-wtf-page"),
    ),
    (
        MODAL_BUTTONS_OLD,
        buttons("zoom-wtf-modal").replace("          <button", "        <button"),
    ),
    (
        "    .zoom-wtf-modal__choice--mac:hover { border-color: #7ec94a; }\n    .zoom-wtf-modal__choice--win:hover { border-color: #3d95ce; }\n",
        HOVER_CSS,
    ),
    (
        "Desktop downloads for Mac and Windows with a simple guided setup.",
        "Digital downloads for Mac, Windows, Linux, iOS, and Android. $10 each, emailed automatically after payment.",
    ),
    (
        "$10 Mac & Windows ZOOM.WTF",
        "$10 1132.WTF — Mac, Windows, Linux, iOS, Android",
    ),
]


def patch_text(text: str) -> tuple[str, int]:
    count = 0
    for old, new in REPLACEMENTS:
        if old in text:
            n = text.count(old)
            text = text.replace(old, new)
            count += n
    return text, count


def apply_five_platforms(root: Path, dry_run: bool = False) -> list[tuple[str, int]]:
    changed: list[tuple[str, int]] = []
    for path in iter_theme_files(root):
        original = path.read_text(encoding="utf-8", errors="replace")
        updated, n = patch_text(original)
        if n == 0 or updated == original:
            continue
        changed.append((str(path.relative_to(root)), n))
        if not dry_run:
            path.write_text(updated, encoding="utf-8")
    return changed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("theme_dir", help="Unzipped Shopify theme folder")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = Path(args.theme_dir).expanduser().resolve()
    if not root.is_dir():
        print(f"Not a directory: {root}", file=sys.stderr)
        return 2

    changed = apply_five_platforms(root, dry_run=args.dry_run)

    if not changed:
        print("No 1132.WTF three-platform copy found. Theme may already be patched, or markup differs.")
        return 1

    action = "Would update" if args.dry_run else "Updated"
    for rel, n in changed:
        print(f"{action} {rel} ({n} replacement(s))")
    print(f"{action} {len(changed)} file(s). Upload the theme ZIP to Shopify to go live.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
