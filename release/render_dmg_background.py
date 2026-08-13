#!/usr/bin/env python3
"""Render the Cadence Soft Graphite DMG background deterministically."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 660
HEIGHT = 420


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    suffix = "Semibold" if weight == "semibold" else "Regular"
    path = Path("/System/Library/Fonts/SFNS.ttf")
    if not path.is_file():
        path = Path(f"/System/Library/Fonts/SFNS{suffix}.ttf")
    return ImageFont.truetype(str(path), size=size)


def centered(draw: ImageDraw.ImageDraw, text: str, y: int, text_font: ImageFont.FreeTypeFont, fill: int) -> None:
    box = draw.textbbox((0, 0), text, font=text_font)
    x = (WIDTH - (box[2] - box[0])) // 2
    draw.text((x, y), text, font=text_font, fill=(fill, fill, fill, 255))


def render(output: Path) -> None:
    image = Image.new("RGBA", (WIDTH, HEIGHT), (35, 35, 35, 255))
    draw = ImageDraw.Draw(image)

    for y in range(HEIGHT):
        distance = abs(y - HEIGHT * 0.45) / HEIGHT
        shade = max(30, min(42, round(42 - distance * 18)))
        draw.line((0, y, WIDTH, y), fill=(shade, shade, shade, 255))

    draw.rounded_rectangle(
        (27, 27, WIDTH - 27, HEIGHT - 27),
        radius=24,
        outline=(61, 61, 61, 255),
        width=2,
    )
    centered(draw, "Cadence", 36, font(26, "semibold"), 239)
    centered(draw, "0.2.0 BETA 1  ·  APPLE SILICON", 69, font(11, "semibold"), 153)

    arrow_y = 212
    draw.line((278, arrow_y, 368, arrow_y), fill=(151, 151, 151, 255), width=3)
    draw.line((351, arrow_y - 13, 368, arrow_y), fill=(151, 151, 151, 255), width=3)
    draw.line((351, arrow_y + 13, 368, arrow_y), fill=(151, 151, 151, 255), width=3)

    # Finder owns the item labels and may render them dark even in a dark system
    # appearance. Quiet graphite plates keep those system labels readable.
    for center_x in (180, 480):
        draw.rounded_rectangle(
            (center_x - 76, 252, center_x + 76, 306),
            radius=16,
            fill=(174, 174, 174, 255),
            outline=(194, 194, 194, 255),
            width=1,
        )

    centered(draw, "Drag Cadence to Applications", 322, font(15, "semibold"), 225)
    centered(draw, "macOS 26+  ·  ad-hoc signed  ·  not notarized", 348, font(10), 151)

    output.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").save(output, format="PNG", optimize=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Cadence DMG background")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    render(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
