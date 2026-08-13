#!/usr/bin/env python3
"""Render the Cadence Soft Graphite DMG background deterministically."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH = 660
HEIGHT = 420
FONT_PATH = Path("/System/Library/Fonts/SFNS.ttf")
FONT_WEIGHTS = {"regular": 400, "medium": 510, "semibold": 600}


def font(size: int, weight: str = "regular", scale: int = 1) -> ImageFont.FreeTypeFont:
    text_font = ImageFont.truetype(str(FONT_PATH), size=size * scale)
    optical_size = max(17, min(size, 96))
    text_font.set_variation_by_axes(
        [100, optical_size, 400, FONT_WEIGHTS[weight]],
    )
    return text_font


def centered(
    draw: ImageDraw.ImageDraw,
    text: str,
    y: int,
    text_font: ImageFont.FreeTypeFont,
    fill: int,
    scale: int,
) -> None:
    box = draw.textbbox((0, 0), text, font=text_font)
    x = (WIDTH * scale - (box[2] - box[0])) // 2
    draw.text(
        (x, y * scale),
        text,
        font=text_font,
        fill=(fill, fill, fill, 255),
    )


def render_scale(scale: int) -> Image.Image:
    pixel_width = WIDTH * scale
    pixel_height = HEIGHT * scale
    image = Image.new("RGBA", (pixel_width, pixel_height), (248, 248, 248, 255))
    draw = ImageDraw.Draw(image)

    for y in range(pixel_height):
        logical_y = y / scale
        vertical = 249 - (logical_y / HEIGHT) * 5
        center_distance = abs(logical_y - 190) / 230
        shade = round(vertical + max(0, 1 - center_distance))
        draw.line((0, y, pixel_width, y), fill=(shade, shade, shade, 255))

    centered(draw, "Cadence", 38, font(29, "semibold", scale), 24, scale)

    arrow_y = 211 * scale
    arrow_start = 285 * scale
    arrow_end = 375 * scale
    arrow_color = (112, 112, 112, 255)
    arrow_width = 2 * scale
    draw.line(
        (arrow_start, arrow_y, arrow_end, arrow_y),
        fill=arrow_color,
        width=arrow_width,
    )
    draw.line(
        (358 * scale, 198 * scale, arrow_end, arrow_y),
        fill=arrow_color,
        width=arrow_width,
    )
    draw.line(
        (358 * scale, 224 * scale, arrow_end, arrow_y),
        fill=arrow_color,
        width=arrow_width,
    )

    centered(
        draw,
        "Drag Cadence to Applications",
        326,
        font(15, "medium", scale),
        44,
        scale,
    )
    centered(
        draw,
        "Apple silicon  ·  macOS 26 or later",
        355,
        font(11, "regular", scale),
        110,
        scale,
    )
    return image


def render(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    retina_output = output.with_name(f"{output.stem}@2x{output.suffix}")
    render_scale(1).convert("RGB").save(
        output,
        format="PNG",
        optimize=True,
        dpi=(72, 72),
    )
    render_scale(2).convert("RGB").save(
        retina_output,
        format="PNG",
        optimize=True,
        dpi=(144, 144),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Cadence DMG background")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    render(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
