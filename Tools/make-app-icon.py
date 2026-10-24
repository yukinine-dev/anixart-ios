#!/usr/bin/env python3
"""Generate the placeholder app icon.

Deliberately generic: a play glyph on the accent gradient, carrying no Anixart
branding, since the port ships none of the original app's assets. Replace
AppIcon.png with your own 1024x1024 artwork and this script becomes unnecessary.

iOS masks the corners itself, so the source must be a full-bleed square with no
transparency and no pre-rounded corners.

Usage: python3 Tools/make-app-icon.py <output.png>
"""

import sys

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # draw oversized, then downsample, for clean edges
TOP = (121, 104, 240)      # Theme.accent
BOTTOM = (58, 44, 150)     # deeper indigo


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2

    side = SIZE * SCALE
    image = Image.new("RGB", (side, side))
    draw = ImageDraw.Draw(image)

    # Diagonal gradient, painted as rows then sheared by drawing per-row offsets.
    for y in range(side):
        t = y / (side - 1)
        colour = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (side, y)], fill=colour)

    # Circle outline
    margin = side * 0.23
    width = side * 0.042
    draw.ellipse(
        [margin, margin, side - margin, side - margin],
        outline=(255, 255, 255),
        width=round(width),
    )

    # Play triangle, nudged right so it reads as centred inside the circle
    cx, cy = side / 2, side / 2
    r = side * 0.135
    draw.polygon(
        [
            (cx - r * 0.62 + side * 0.012, cy - r),
            (cx - r * 0.62 + side * 0.012, cy + r),
            (cx + r * 0.95 + side * 0.012, cy),
        ],
        fill=(255, 255, 255),
    )

    image.resize((SIZE, SIZE), Image.LANCZOS).save(sys.argv[1], "PNG", optimize=True)
    print(f"wrote {sys.argv[1]} ({SIZE}x{SIZE})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
