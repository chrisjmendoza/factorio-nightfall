"""Draws Nightfall's thumbnail: cold night with one warm pool of lamplight.

The mod is a colour effect, so the thumbnail has to be the colour effect --
a cool blue field with a single warm light working against it, which is the
whole pitch in one image. Supersampled 8x before the downscale so the glow
gradients band as little as possible at 144px.

Run from the mod root: python tools/make_thumbnail.py
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SS = 8  # supersample factor
SIZE = 144
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The same two profiles the mod uses, read as colours rather than as weights.
NIGHT_TOP = (6, 10, 26)
NIGHT_LOW = (14, 24, 54)
HORIZON = (34, 40, 74)
LAMP_WARM = (255, 196, 96)

STARS = [  # x, y, brightness, in 0..1 of the canvas
    (0.12, 0.10, 0.9), (0.28, 0.19, 0.5), (0.44, 0.08, 0.7),
    (0.62, 0.16, 0.45), (0.78, 0.09, 0.8), (0.89, 0.24, 0.55),
    (0.19, 0.30, 0.4), (0.71, 0.31, 0.35), (0.53, 0.25, 0.6),
    (0.35, 0.36, 0.3), (0.94, 0.42, 0.35), (0.06, 0.44, 0.3),
]


def vertical_gradient(size):
    """Deep navy overhead easing to a slightly lifted horizon."""
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    horizon = int(size * 0.72)

    for y in range(size):
        if y < horizon:
            t = y / horizon
            # Eased so most of the frame stays genuinely dark and the lift
            # happens close to the horizon, the way a real night sky reads.
            t = t ** 2.2
            top, low = NIGHT_TOP, HORIZON
        else:
            t = (y - horizon) / max(1, size - horizon)
            top, low = HORIZON, NIGHT_LOW
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(int(top[i] + (low[i] - top[i]) * t) for i in range(3)),
        )
    return img


def add_stars(img, size):
    draw = ImageDraw.Draw(img)
    for sx, sy, weight in STARS:
        x, y = sx * size, sy * size
        r = size * 0.0035 * (0.6 + weight)
        # Cool white: the sky is blue-biased, so stars must be too or they
        # read as dust on the screen.
        value = int(150 + 105 * weight)
        draw.ellipse([x - r, y - r, x + r, y + r],
                     fill=(value, int(value * 0.97), 255))
    return img


def lamp_glow(size):
    """The warm pool, as an additive layer so it lifts rather than paints."""
    glow = Image.new("RGB", (size, size), (0, 0, 0))
    draw = ImageDraw.Draw(glow)

    cx, cy = size * 0.5, size * 0.60
    # Drawn as concentric ellipses with a falloff, then blurred. Wider than
    # tall because it is light landing on ground seen from above.
    steps = 90
    outer_w, outer_h = size * 0.40, size * 0.26
    for i in range(steps, 0, -1):
        t = i / steps
        falloff = (1 - t) ** 2.8
        value = tuple(int(c * falloff * 0.85) for c in LAMP_WARM)
        w, h = outer_w * t, outer_h * t
        draw.ellipse([cx - w, cy - h, cx + w, cy + h], fill=value)

    return glow.filter(ImageFilter.GaussianBlur(size * 0.022))


def lamp(img, size):
    """A small lamp head above the pool, so the light has a visible source."""
    draw = ImageDraw.Draw(img)
    cx = size * 0.5
    top = size * 0.40

    # A post up to the top edge. Without it the lit shade reads as a moon at
    # 144px, which is the wrong story entirely -- the point is that somebody
    # built this light.
    post_w = size * 0.011
    draw.rectangle([cx - post_w, 0, cx + post_w, top + size * 0.01],
                   fill=(20, 24, 42))

    # Shade: a trapezoid, dark against the sky rather than lit, because the
    # light it throws is pointing away from the camera.
    shade_w, shade_h = size * 0.115, size * 0.055
    draw.polygon(
        [(cx - shade_w, top + shade_h), (cx + shade_w, top + shade_h),
         (cx + shade_w * 0.42, top), (cx - shade_w * 0.42, top)],
        fill=(24, 28, 46),
    )
    # The bulb itself, the one blown-out spot in the frame.
    bulb_r = size * 0.030
    draw.ellipse(
        [cx - bulb_r, top + shade_h - bulb_r * 0.75,
         cx + bulb_r, top + shade_h + bulb_r * 0.75],
        fill=(255, 238, 198),
    )
    return img


def add(base, layer):
    """Additive composite, clamped -- light adds, it does not replace."""
    out = Image.new("RGB", base.size)
    bp, lp, op = base.load(), layer.load(), out.load()
    for y in range(base.size[1]):
        for x in range(base.size[0]):
            b, l = bp[x, y], lp[x, y]
            op[x, y] = (min(255, b[0] + l[0]),
                        min(255, b[1] + l[1]),
                        min(255, b[2] + l[2]))
    return out


def vignette(img, size):
    """Pulls the corners down, which is what sells it as a dark scene."""
    mask = Image.new("L", (size, size))
    mp = mask.load()
    cx = cy = size / 2
    longest = math.hypot(cx, cy)
    for y in range(size):
        for x in range(size):
            t = math.hypot(x - cx, y - cy) / longest
            mp[x, y] = int(255 * max(0.0, 1 - (t ** 2.4) * 0.85))
    return Image.composite(img, Image.new("RGB", (size, size), NIGHT_TOP), mask)


def main():
    size = SIZE * SS

    sky = vertical_gradient(size)
    sky = add_stars(sky, size)
    scene = add(sky, lamp_glow(size))
    scene = lamp(scene, size)
    scene = vignette(scene, size)

    final = scene.resize((SIZE, SIZE), Image.LANCZOS).convert("RGBA")
    out = os.path.join(ROOT, "thumbnail.png")
    final.save(out)
    print(f"  thumbnail.png  {final.width}x{final.height}")

    # Portal page asset, kept out of the zip by the packer.
    large = scene.resize((720, 720), Image.LANCZOS).convert("RGBA")
    large.save(os.path.join(ROOT, "thumbnail_720.png"))
    print(f"  thumbnail_720.png  {large.width}x{large.height}")


if __name__ == "__main__":
    main()
