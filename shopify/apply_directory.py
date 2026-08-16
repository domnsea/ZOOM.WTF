#!/usr/bin/env python3
"""Install the ZOOM DIRECTORY page into a ballroom Shopify theme export.

Copies the directory snippet/template/asset and injects
`{% render 'zoom-directory' %}` before </body> in layout/theme.liquid.

Usage:
  python3 shopify/apply_directory.py /path/to/unzipped-theme
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

RENDER = "{% render 'zoom-directory' %}"


def copy_patch(patch_root: Path, theme_root: Path) -> list[str]:
    copied: list[str] = []
    mapping = {
        "snippets/zoom-directory.liquid": "snippets/zoom-directory.liquid",
        "templates/page.zoom-directory.liquid": "templates/page.zoom-directory.liquid",
        "sections/zoom-directory.liquid": "sections/zoom-directory.liquid",
        "assets/zoom-directory.json": "assets/zoom-directory.json",
        "assets/ROOMS.txt": "assets/ROOMS.txt",
    }
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
    needle = "</body>"
    if needle not in text and "</body>" not in text.lower():
        return text + "\n" + RENDER + "\n", 1
    idx = text.lower().rfind("</body>")
    if idx == -1:
        return text + "\n" + RENDER + "\n", 1
    return text[:idx] + RENDER + "\n" + text[idx:], 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Add the HOSTBOT2 ZOOM DIRECTORY page to a theme export.")
    parser.add_argument("theme", type=Path, help="Unzipped theme folder")
    args = parser.parse_args(argv)
    theme_root = args.theme.expanduser().resolve()
    if not theme_root.is_dir():
        print(f"Not a directory: {theme_root}", file=sys.stderr)
        return 2
    patch_root = Path(__file__).resolve().parent / "theme-patch"
    copied = copy_patch(patch_root, theme_root)
    injected = inject_render(theme_root)
    print("Copied " + ", ".join(copied))
    if injected:
        print("Injected {% render 'zoom-directory' %} into layout/theme.liquid")
    else:
        print("layout/theme.liquid already renders zoom-directory (or was missing)")
    print("Upload the theme ZIP. Edit assets/ROOMS.txt to name unknown numbers. Keep zoom-directory.json updated from HOSTBOT2.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
