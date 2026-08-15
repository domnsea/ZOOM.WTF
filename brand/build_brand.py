#!/usr/bin/env python3
"""Generate every 1132.WTF branding asset from a single geometry definition.

The icon is a seven-segment "1132" error-code display on a dark rounded tile.
Both the vector master (icon.svg) and all platform rasters come from the same
segment geometry so they can never drift apart.

Usage: python3 brand/build_brand.py [--out brand/out]
"""

from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
BRAND = json.loads((HERE / "brand.json").read_text())
C = BRAND["colors"]

# The icon is designed in a 1024x1024 space and scaled from there.
DESIGN = 1024
RADIUS_PCT = BRAND["icon"]["corner_radius_pct"] / 100.0
RING_W = 11.0
DIGITS = BRAND["icon"]["digits"]

CELL_W, CELL_H = 230.0, 300.0
COL_GAP, ROW_GAP = 62.0, 58.0
SEG_T, SEG_GAP = 46.0, 11.0
BLOCK_CX, BLOCK_CY = 512.0, 462.0
BAR_Y, BAR_H = 852.0, 38.0

# Which of the seven segments are lit for each digit.
SEVEN_SEG = {
    "0": "abcdef",
    "1": "bc",
    "2": "abdeg",
    "3": "abcdg",
    "4": "bcfg",
    "5": "acdfg",
    "6": "acdefg",
    "7": "abc",
    "8": "abcdefg",
    "9": "abcdfg",
}

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-ExtraBold.ttf",
    "/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


# --------------------------------------------------------------------------
# Segment geometry (design-space coordinates)
# --------------------------------------------------------------------------


def _hseg(cy: float, x0: float, x1: float, t: float) -> list[tuple[float, float]]:
    h = t / 2.0
    return [
        (x0, cy),
        (x0 + h, cy - h),
        (x1 - h, cy - h),
        (x1, cy),
        (x1 - h, cy + h),
        (x0 + h, cy + h),
    ]


def _vseg(cx: float, y0: float, y1: float, t: float) -> list[tuple[float, float]]:
    h = t / 2.0
    return [
        (cx, y0),
        (cx + h, y0 + h),
        (cx + h, y1 - h),
        (cx, y1),
        (cx - h, y1 - h),
        (cx - h, y0 + h),
    ]


def segment_polys(x: float, y: float, w: float, h: float) -> dict[str, list[tuple[float, float]]]:
    """Return the polygon for all seven segments of a digit cell."""
    t, g = SEG_T, SEG_GAP
    y_top, y_mid, y_bot = y + t / 2, y + h / 2, y + h - t / 2
    x_left, x_right = x + t / 2, x + w - t / 2
    return {
        "a": _hseg(y_top, x_left + g, x_right - g, t),
        "g": _hseg(y_mid, x_left + g, x_right - g, t),
        "d": _hseg(y_bot, x_left + g, x_right - g, t),
        "f": _vseg(x_left, y_top + g, y_mid - g, t),
        "b": _vseg(x_right, y_top + g, y_mid - g, t),
        "e": _vseg(x_left, y_mid + g, y_bot - g, t),
        "c": _vseg(x_right, y_mid + g, y_bot - g, t),
    }


def digit_cells() -> list[tuple[str, float, float]]:
    """Lay the four digits out as a 2x2 block; returns (digit, x, y) per cell."""
    block_w = 2 * CELL_W + COL_GAP
    block_h = 2 * CELL_H + ROW_GAP
    x0 = BLOCK_CX - block_w / 2
    y0 = BLOCK_CY - block_h / 2
    cells = []
    for index, digit in enumerate(DIGITS):
        row, col = divmod(index, 2)
        cells.append(
            (digit, x0 + col * (CELL_W + COL_GAP), y0 + row * (CELL_H + ROW_GAP))
        )
    return cells


# --------------------------------------------------------------------------
# Raster icon
# --------------------------------------------------------------------------


def _vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    w, h = size
    top_rgb, bottom_rgb = hex_rgb(top), hex_rgb(bottom)
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        f = y / max(1, h - 1)
        grad.putpixel(
            (0, y),
            tuple(round(top_rgb[i] + (bottom_rgb[i] - top_rgb[i]) * f) for i in range(3)),
        )
    return grad.resize((w, h), Image.NEAREST)


def _diagonal_gradient(size: tuple[int, int], start: str, end: str) -> Image.Image:
    w, h = size
    a, b = hex_rgb(start), hex_rgb(end)
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            f = (x + y) / 126.0
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * f) for i in range(3))
    return small.resize((w, h), Image.BICUBIC)


def render_icon(size: int, *, tile: bool = True, scale: int = 4) -> Image.Image:
    """Render the app icon at `size` px, supersampled for clean edges."""
    detail = size >= 64
    ss = max(1, min(scale, max(1, 2048 // max(size, 1))))
    S = size * ss
    k = S / DESIGN  # design-space -> pixel scale

    def P(points):
        return [(px * k, py * k) for px, py in points]

    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # Rounded tile with a vertical gradient body.
    radius = RADIUS_PCT * S
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
    if tile:
        body = _vertical_gradient((S, S), C["bg_top"], C["bg_bottom"]).convert("RGBA")
        base.paste(body, (0, 0), mask)

        # Gradient hairline ring just inside the edge.
        ring_w = max(1.0, RING_W * k)
        ring_mask = Image.new("L", (S, S), 0)
        rd = ImageDraw.Draw(ring_mask)
        inset = ring_w / 2 + 1
        rd.rounded_rectangle(
            [inset, inset, S - 1 - inset, S - 1 - inset],
            radius=max(1.0, radius - inset),
            outline=255,
            width=max(1, round(ring_w)),
        )
        ring = _diagonal_gradient((S, S), C["accent"], C["accent2"]).convert("RGBA")
        base.paste(ring, (0, 0), ring_mask)

    # Unlit segments, like a real LCD, only where they will read as detail.
    if detail:
        off = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        od = ImageDraw.Draw(off)
        for digit, cx, cy in digit_cells():
            polys = segment_polys(cx, cy, CELL_W, CELL_H)
            for name, poly in polys.items():
                if name not in SEVEN_SEG[digit]:
                    od.polygon(P(poly), fill=hex_rgb(C["accent"]) + (26,))
        base.alpha_composite(off)

    # Lit segments plus glow.
    lit = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(lit)
    for digit, cx, cy in digit_cells():
        polys = segment_polys(cx, cy, CELL_W, CELL_H)
        for name in SEVEN_SEG[digit]:
            ld.polygon(P(polys[name]), fill=hex_rgb(C["accent"]) + (255,))

    if detail:
        glow = lit.filter(ImageFilter.GaussianBlur(radius=max(1.0, 26 * k)))
        glow.putalpha(glow.getchannel("A").point(lambda v: int(v * 0.55)))
        base.alpha_composite(glow)
    base.alpha_composite(lit)

    # Accent bar under the digits.
    bar_mask = Image.new("L", (S, S), 0)
    block_w = 2 * CELL_W + COL_GAP
    bx0 = BLOCK_CX - block_w / 2
    ImageDraw.Draw(bar_mask).rounded_rectangle(
        [bx0 * k, BAR_Y * k, (bx0 + block_w) * k, (BAR_Y + BAR_H) * k],
        radius=(BAR_H / 2) * k,
        fill=255,
    )
    bar = _diagonal_gradient((S, S), C["accent"], C["accent2"]).convert("RGBA")
    base.paste(bar, (0, 0), bar_mask)

    if not tile:
        # Adaptive-icon foreground: keep art inside the safe zone, no tile.
        base.putalpha(base.getchannel("A"))

    return base.resize((size, size), Image.LANCZOS) if ss > 1 else base


# --------------------------------------------------------------------------
# Vector master
# --------------------------------------------------------------------------


def render_svg() -> str:
    def poly(points, fill, opacity=1.0):
        pts = " ".join(f"{x:.2f},{y:.2f}" for x, y in points)
        op = "" if opacity >= 1.0 else f' opacity="{opacity}"'
        return f'    <polygon points="{pts}" fill="{fill}"{op}/>'

    radius = RADIUS_PCT * DESIGN
    block_w = 2 * CELL_W + COL_GAP
    bx0 = BLOCK_CX - block_w / 2

    off_parts, lit_parts = [], []
    for digit, cx, cy in digit_cells():
        polys = segment_polys(cx, cy, CELL_W, CELL_H)
        for name, points in polys.items():
            if name in SEVEN_SEG[digit]:
                lit_parts.append(poly(points, C["accent"]))
            else:
                off_parts.append(poly(points, C["accent"], 0.10))

    ring_inset = RING_W / 2
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!-- Generated by brand/build_brand.py - do not edit by hand. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {DESIGN} {DESIGN}" width="{DESIGN}" height="{DESIGN}">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{C['bg_top']}"/>
      <stop offset="1" stop-color="{C['bg_bottom']}"/>
    </linearGradient>
    <linearGradient id="edge" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{C['accent']}"/>
      <stop offset="1" stop-color="{C['accent2']}"/>
    </linearGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="26" result="b"/>
      <feComponentTransfer in="b" result="s">
        <feFuncA type="linear" slope="0.55"/>
      </feComponentTransfer>
      <feMerge><feMergeNode in="s"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="0" y="0" width="{DESIGN}" height="{DESIGN}" rx="{radius:.2f}" ry="{radius:.2f}" fill="url(#body)"/>
  <rect x="{ring_inset:.2f}" y="{ring_inset:.2f}" width="{DESIGN - RING_W:.2f}" height="{DESIGN - RING_W:.2f}"
        rx="{radius - ring_inset:.2f}" ry="{radius - ring_inset:.2f}"
        fill="none" stroke="url(#edge)" stroke-width="{RING_W}"/>
  <g id="segments-off">
{chr(10).join(off_parts)}
  </g>
  <g id="segments-lit" filter="url(#glow)">
{chr(10).join(lit_parts)}
  </g>
  <rect x="{bx0:.2f}" y="{BAR_Y:.2f}" width="{block_w:.2f}" height="{BAR_H:.2f}"
        rx="{BAR_H / 2:.2f}" ry="{BAR_H / 2:.2f}" fill="url(#edge)"/>
</svg>
"""


# --------------------------------------------------------------------------
# Platform container formats
# --------------------------------------------------------------------------

ICNS_TYPES = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512),
]


def write_icns(path: Path, icons: dict[int, Image.Image]) -> None:
    """Write a PNG-based .icns, which macOS 10.7+ reads natively."""
    import io

    chunks = b""
    for type_code, size in ICNS_TYPES:
        buf = io.BytesIO()
        icons[size].save(buf, format="PNG")
        data = buf.getvalue()
        chunks += type_code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def write_wordmark(path: Path, width: int = 1600) -> None:
    """Horizontal lockup: icon tile + '1132.WTF' + tagline.

    Drawn on an opaque dark panel so it stays legible on light and dark
    README backgrounds alike.
    """
    h = width // 4
    img = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    panel = Image.new("L", (width, h), 0)
    ImageDraw.Draw(panel).rounded_rectangle(
        [0, 0, width - 1, h - 1], radius=h * 0.14, fill=255
    )
    img.paste(
        _vertical_gradient((width, h), C["bg_top"], C["bg_bottom"]).convert("RGBA"),
        (0, 0),
        panel,
    )
    pad = h // 8
    tile = h - 2 * pad
    img.alpha_composite(render_icon(tile), (pad, pad))

    draw = ImageDraw.Draw(img)
    text_x = pad + tile + int(h * 0.16)
    title_font = load_font(int(h * 0.40))
    sub_font = load_font(int(h * 0.145))

    title_y = int(h * 0.24)
    draw.text((text_x, title_y), "1132", font=title_font, fill=hex_rgb(C["accent"]))
    span = draw.textlength("1132", font=title_font)
    draw.text((text_x + span, title_y), ".WTF", font=title_font, fill=hex_rgb(C["ink"]))
    draw.text(
        (text_x, title_y + int(h * 0.46)),
        BRAND["tagline"].upper(),
        font=sub_font,
        fill=hex_rgb(C["accent2"]),
    )
    path.write_bytes(b"")
    img.save(path)


ANDROID_MIPMAPS = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# (size, idiom, scale, filename-friendly label) for the classic iOS icon set.
IOS_ICONS = [
    (20, "iphone", 2), (20, "iphone", 3),
    (29, "iphone", 2), (29, "iphone", 3),
    (40, "iphone", 2), (40, "iphone", 3),
    (60, "iphone", 2), (60, "iphone", 3),
    (20, "ipad", 1), (20, "ipad", 2),
    (29, "ipad", 1), (29, "ipad", 2),
    (40, "ipad", 1), (40, "ipad", 2),
    (76, "ipad", 2),
    (83.5, "ipad", 2),
    (1024, "ios-marketing", 1),
]

PNG_SIZES = [16, 20, 24, 32, 40, 48, 64, 72, 96, 128, 144, 192, 256, 512, 1024]
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]
LINUX_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(HERE / "out"))
    args = parser.parse_args()
    out = Path(args.out)

    icons: dict[int, Image.Image] = {}

    def icon(size: int) -> Image.Image:
        if size not in icons:
            icons[size] = render_icon(size)
        return icons[size]

    (out / "png").mkdir(parents=True, exist_ok=True)
    for size in PNG_SIZES:
        icon(size).save(out / "png" / f"icon_{size}.png")

    (out / "icon.svg").write_text(render_svg())

    icon(1024).save(out / "icon.png")
    # Each .ico frame is rendered at its own size rather than downsampled from
    # one bitmap, so the 16/24/32 px frames keep crisp segment edges.
    ico_frames = [icon(s) for s in ICO_SIZES]
    ico_frames[-1].save(
        out / "1132.WTF.ico",
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
        append_images=ico_frames[:-1],
    )

    for size in {s for _, s in ICNS_TYPES}:
        icon(size)
    write_icns(out / "AppIcon.icns", icons)

    write_wordmark(out / "wordmark.png")

    # Linux freedesktop icon theme layout.
    for size in LINUX_SIZES:
        d = out / "linux" / "hicolor" / f"{size}x{size}" / "apps"
        d.mkdir(parents=True, exist_ok=True)
        icon(size).save(d / f"{BRAND['slug']}.png")
    (out / "linux" / "hicolor" / "scalable" / "apps").mkdir(parents=True, exist_ok=True)
    (out / "linux" / "hicolor" / "scalable" / "apps" / f"{BRAND['slug']}.svg").write_text(
        render_svg()
    )

    # Android legacy mipmaps + adaptive icon layers.
    for bucket, size in ANDROID_MIPMAPS.items():
        d = out / "android" / f"mipmap-{bucket}"
        d.mkdir(parents=True, exist_ok=True)
        icon(size).save(d / "ic_launcher.png")
        rounded = icon(size).copy()
        circle = Image.new("L", (size, size), 0)
        ImageDraw.Draw(circle).ellipse([0, 0, size - 1, size - 1], fill=255)
        rounded.putalpha(circle)
        rounded.save(d / "ic_launcher_round.png")
        # Adaptive foreground is 108dp with the art inside the 66dp safe zone.
        fg_px = round(size * 108 / 48)
        art = round(fg_px * 0.58)
        fg = Image.new("RGBA", (fg_px, fg_px), (0, 0, 0, 0))
        fg.alpha_composite(render_icon(art, tile=False), ((fg_px - art) // 2,) * 2)
        fg.save(d / "ic_launcher_foreground.png")

    # iOS asset catalog.
    ios_dir = out / "ios" / "AppIcon.appiconset"
    ios_dir.mkdir(parents=True, exist_ok=True)
    images = []
    seen: set[int] = set()
    for pt, idiom, scale in IOS_ICONS:
        px = round(pt * scale)
        label = f"{pt:g}x{pt:g}"
        filename = f"icon_{px}.png"
        if px not in seen:
            icon(px).save(ios_dir / filename)
            seen.add(px)
        images.append(
            {"size": label, "idiom": idiom, "filename": filename, "scale": f"{scale}x"}
        )
    (ios_dir / "Contents.json").write_text(
        json.dumps(
            {"images": images, "info": {"version": 1, "author": "build_brand.py"}},
            indent=2,
        )
        + "\n"
    )

    # Windows/macOS/Linux shared previews used by READMEs.
    print(f"[ok] brand assets written to {out}")
    for path in sorted(out.rglob("*")):
        if path.is_file():
            print(f"     {path.relative_to(out)} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
