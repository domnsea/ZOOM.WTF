#!/usr/bin/env python3
"""Install the looping header logo video, ZOOM DIRECTORY nav link, and
sitewide banner offset into a ballroom Shopify theme export.

Usage:
  python3 shopify/apply_header.py /path/to/unzipped-theme
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

RENDER = "{% render 'site-header-chrome' %}"
SKIP_DIRS = {".git", "node_modules", ".theme-check"}
TEXT_SUFFIXES = {".liquid", ".json", ".js", ".css", ".html"}

VIDEO_MARKUP = """<video
      class="ballroom-header-logo-video"
      autoplay
      muted
      loop
      playsinline
      preload="auto"
      poster="{{ 'ballroom-header-logo.png' | asset_url }}"
      aria-label="Ballroom.WTF"
    >
      <source src="{{ 'ballroom-header-logo.mp4' | asset_url }}" type="video/mp4">
    </video>
    """

DIRECTORY_DESKTOP = """                  <div class="nav-mnav-item nav-mnav-item--leaf"><a
  class="nav-link nav-link--classic nav-mnav-leaf-link nav-link--zoom-directory nav-link--brand-white"
  href="/pages/zoom-directory"
>
  ZOOM DIRECTORY
</a>
</div>
"""

DIRECTORY_MOBILE_BTN = (
    '<a class="nav-mobile-quick__btn nav-link--brand-white nav-link--zoom-directory" '
    'href="/pages/zoom-directory">ZOOM DIRECTORY</a>'
)

DIRECTORY_MOBILE_HUB = (
    '<a class="nav-link nav-link--classic nav-link--mnav-sub nav-link--zoom-directory nav-link--brand-white" '
    'href="/pages/zoom-directory">ZOOM DIRECTORY</a>'
)


def iter_theme_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        yield path


def copy_patch(patch_root: Path, theme_root: Path) -> list[str]:
    grok = patch_root / "assets" / "grok-video-019f7d62-c15f-7552-908b-b6a0e4393ee6.mp4"
    logo_mp4 = patch_root / "assets" / "ballroom-header-logo.mp4"
    if grok.is_file():
        shutil.copy2(grok, logo_mp4)

    mapping = {
        "snippets/site-header-chrome.liquid": "snippets/site-header-chrome.liquid",
        "snippets/ballroom-header-logo.liquid": "snippets/ballroom-header-logo.liquid",
        "assets/ballroom-header-logo.mp4": "assets/ballroom-header-logo.mp4",
        "assets/ballroom-header-logo.png": "assets/ballroom-header-logo.png",
    }
    copied: list[str] = []
    for src_rel, dest_rel in mapping.items():
        src = patch_root / src_rel
        dest = theme_root / dest_rel
        if not src.is_file():
            raise SystemExit(f"Missing patch file: {src}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        copied.append(dest_rel)
    return copied


def inject_render(theme_root: Path) -> bool:
    layout = theme_root / "layout" / "theme.liquid"
    if not layout.is_file():
        return False
    text = layout.read_text(encoding="utf-8", errors="replace")
    if RENDER in text:
        return False
    updated, n = _inject(text)
    if n:
        layout.write_text(updated, encoding="utf-8")
        return True
    return False


def _inject(text: str) -> tuple[str, int]:
    idx = text.lower().rfind("</body>")
    if idx == -1:
        return text + "\n" + RENDER + "\n", 1
    return text[:idx] + RENDER + "\n" + text[idx:], 1


def patch_header_text(text: str) -> tuple[str, int]:
    original = text
    count = 0

    if 'class="ballroom-header-lockup"' in text and "ballroom-header-lockup--video" not in text:
        text = text.replace(
            'class="ballroom-header-lockup"',
            'class="ballroom-header-lockup ballroom-header-lockup--video"',
            1,
        )
        count += 1

    if "ballroom-header-logo-video" not in text and "ballroom-header-logo-img" in text:
        text, n = re.subn(
            r"<img(\s+class=\"ballroom-header-logo-img\")",
            VIDEO_MARKUP + r"<img\1",
            text,
            count=1,
            flags=re.I,
        )
        count += n

    if 'class="ballroom-header-logo-img"' in text and "ballroom-header-logo-img--fallback" not in text:
        text = text.replace(
            'class="ballroom-header-logo-img"',
            'class="ballroom-header-logo-img ballroom-header-logo-img--fallback"',
            1,
        )
        count += 1

    if 'href="/pages/zoom-directory"' not in text and 'href="/pages/zoom-wtf"' in text:
        desktop = re.search(
            r'(<div class="nav-mnav-item nav-mnav-item--leaf"><a\s+class="nav-link[^"]*nav-link--zoom-wtf[^"]*"\s+href="/pages/zoom-wtf"\s*>\s*1132\.WTF\s*</a>\s*</div>)',
            text,
            flags=re.I | re.S,
        )
        if desktop:
            text = text.replace(desktop.group(1), desktop.group(1) + "\n" + DIRECTORY_DESKTOP, 1)
            count += 1
        mobile_btn = re.search(
            r'(<a class="nav-mobile-quick__btn[^"]*" href="/pages/zoom-wtf">1132\.WTF</a>)',
            text,
            flags=re.I,
        )
        if mobile_btn:
            text = text.replace(mobile_btn.group(1), mobile_btn.group(1) + "\n          " + DIRECTORY_MOBILE_BTN, 1)
            count += 1
        hub = re.search(
            r'(<a class="nav-link[^"]*" href="/pages/zoom-wtf">1132\.WTF</a>)',
            text,
            flags=re.I,
        )
        if hub and DIRECTORY_MOBILE_HUB not in text:
            text = text.replace(hub.group(1), hub.group(1) + "\n                " + DIRECTORY_MOBILE_HUB, 1)
            count += 1

    replacements = [
        ("--nav-height: 68px;", "--nav-height: 240px;"),
        ("var(--below-fixed, 72px)", "var(--below-fixed, 240px)"),
        ("var(--nav-height, 68px)", "var(--below-fixed, 240px)"),
    ]
    for old, new in replacements:
        if old in text:
            n = text.count(old)
            text = text.replace(old, new)
            count += n

    if text == original:
        return text, 0
    return text, count


def apply_header(theme_root: Path, patch_root: Path | None = None, dry_run: bool = False) -> dict:
    theme_root = theme_root.expanduser().resolve()
    if patch_root is None:
        patch_root = Path(__file__).resolve().parent / "theme-patch"
    copied = [] if dry_run else copy_patch(patch_root, theme_root)
    changed = []
    for path in iter_theme_files(theme_root):
        original = path.read_text(encoding="utf-8", errors="replace")
        updated, n = patch_header_text(original)
        if n == 0 or updated == original:
            continue
        changed.append((str(path.relative_to(theme_root)), n))
        if not dry_run:
            path.write_text(updated, encoding="utf-8")
    injected = False if dry_run else inject_render(theme_root)
    return {"copied": copied, "changed": changed, "injected": injected}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("theme", type=Path, help="Unzipped theme folder")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    theme_root = args.theme.expanduser().resolve()
    if not theme_root.is_dir():
        print(f"Not a directory: {theme_root}", file=sys.stderr)
        return 2
    result = apply_header(theme_root, dry_run=args.dry_run)
    action = "Would update" if args.dry_run else "Updated"
    if result["copied"]:
        print("Copied " + ", ".join(result["copied"]))
    for rel, n in result["changed"]:
        print(f"{action} {rel} ({n} replacement(s))")
    if result["injected"]:
        print("Injected {% render 'site-header-chrome' %} into layout/theme.liquid")
    elif (theme_root / "layout" / "theme.liquid").is_file() and not args.dry_run:
        print("layout/theme.liquid already renders site-header-chrome (or was missing)")
    print("Upload the theme ZIP. Header video is assets/ballroom-header-logo.mp4.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
