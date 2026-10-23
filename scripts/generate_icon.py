#!/usr/bin/env python3
"""Draws the Pinscape app icon (light, dark and tinted) into the asset catalog.

    python3 scripts/generate_icon.py

Needs Pillow. The icon is a white map pin over a sunset gradient, standing on
two soft rings: a thought, anchored to a place.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # supersample for smooth edges
S = SIZE * SCALE
OUT = os.path.join(os.path.dirname(__file__), "..", "Pinscape", "Resources", "Assets.xcassets", "AppIcon.appiconset")


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def diagonal_gradient(stops):
    """Top-left to bottom-right gradient through the given (position, colour) stops."""
    small = 256
    image = Image.new("RGB", (small, small))
    pixels = image.load()
    for y in range(small):
        for x in range(small):
            t = (x * 0.45 + y * 0.55) / (small - 1)
            for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
                if p0 <= t <= p1:
                    pixels[x, y] = lerp(c0, c1, (t - p0) / (p1 - p0))
                    break
            else:
                pixels[x, y] = stops[-1][1]
    return image.resize((S, S), Image.BICUBIC)


def radial_glow(center, radius, color, strength):
    glow = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(glow)
    cx, cy = center
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=int(255 * strength))
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.55))
    layer = Image.new("RGB", (S, S), color)
    return layer, glow


def pin_mask(cx, cy, r, tip_y):
    """A teardrop: a circle whose sides run tangent down to a point."""
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)
    d = tip_y - cy
    # Angle from the centre to the tangent points.
    theta = math.acos(r / d)
    left = (cx - r * math.sin(theta), cy + r * math.cos(theta))
    right = (cx + r * math.sin(theta), cy + r * math.cos(theta))
    points = [right]
    start = math.pi / 2 - theta
    end = math.pi / 2 + theta - 2 * math.pi
    steps = 240
    for i in range(steps + 1):
        a = start + (end - start) * i / steps
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    points.append(left)
    points.append((cx, tip_y))
    draw.polygon(points, fill=255)
    return mask


def ring_mask(cx, cy, rx, ry, width):
    mask = Image.new("L", (S, S), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=255, width=width)
    return mask


def compose(background, pin_fill, hole_fill, ring_color, ring_alpha, shadow_alpha):
    canvas = background.convert("RGBA")

    cx, cy = S / 2, S * 0.40
    r = S * 0.205
    tip_y = S * 0.735

    # Rings on the ground, where the pin stands.
    for rx, ry, alpha, width in [(S * 0.30, S * 0.085, ring_alpha, int(S * 0.016)), (S * 0.20, S * 0.055, ring_alpha * 1.35, int(S * 0.016))]:
        mask = ring_mask(cx, tip_y, rx, ry, width).point(lambda v, a=alpha: int(v * min(a, 1)))
        canvas = Image.composite(Image.new("RGBA", (S, S), ring_color + (255,)), canvas, mask)

    shape = pin_mask(cx, cy, r, tip_y)

    # Soft drop shadow.
    shadow = shape.filter(ImageFilter.GaussianBlur(S * 0.03)).point(lambda v: int(v * shadow_alpha))
    shadow = ImageChops.offset(shadow, 0, int(S * 0.025))
    canvas = Image.composite(Image.new("RGBA", (S, S), (60, 0, 30, 255)), canvas, shadow)

    # The pin itself.
    if isinstance(pin_fill, Image.Image):
        canvas = Image.composite(pin_fill.convert("RGBA"), canvas, shape)
    else:
        canvas = Image.composite(Image.new("RGBA", (S, S), pin_fill + (255,)), canvas, shape)

    # The hole in the pin head shows the sky behind it.
    hole = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hole).ellipse([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42], fill=255)
    if isinstance(hole_fill, Image.Image):
        canvas = Image.composite(hole_fill.convert("RGBA"), canvas, hole)
    else:
        canvas = Image.composite(Image.new("RGBA", (S, S), hole_fill + (255,)), canvas, hole)

    # A gentle sheen across the top of the pin head.
    sheen = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sheen).ellipse([cx - r * 0.95, cy - r * 1.05, cx + r * 0.6, cy - r * 0.05], fill=70)
    sheen = ImageChops.multiply(sheen.filter(ImageFilter.GaussianBlur(S * 0.02)), shape)
    canvas = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 255)), canvas, sheen)

    return canvas.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    sunset = diagonal_gradient([(0.0, hex_rgb("#FF9A44")), (0.5, hex_rgb("#FF4F5A")), (1.0, hex_rgb("#E02F86"))])
    glow, glow_mask = radial_glow((S * 0.22, S * 0.12), S * 0.45, (255, 214, 170), 0.55)
    sunset = Image.composite(glow, sunset, glow_mask)

    light = compose(sunset, (255, 255, 255), sunset, (255, 255, 255), 0.42, 0.45)
    light.save(os.path.join(OUT, "AppIcon.png"))

    night = diagonal_gradient([(0.0, hex_rgb("#2A1238")), (1.0, hex_rgb("#0E0716"))])
    dark = compose(night, sunset, night, (255, 120, 110), 0.38, 0.6)
    dark.save(os.path.join(OUT, "AppIcon-Dark.png"))

    black = Image.new("RGB", (S, S), (0, 0, 0))
    tinted = compose(black, (255, 255, 255), black, (200, 200, 200), 0.5, 0.0).convert("L")
    tinted.save(os.path.join(OUT, "AppIcon-Tinted.png"))
    print("Wrote icons to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
