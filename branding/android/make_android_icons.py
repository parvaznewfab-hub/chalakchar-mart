"""Android icon sources for the "হাট ২" mark (house roof + orange bag).

Run from the project root:

    python branding/android/make_android_icons.py
    dart run flutter_launcher_icons

This script writes:
  branding/android/ic_launcher_foreground-1024.png  adaptive foreground (no inset)
  branding/android/ic_launcher_monochrome-1024.png  Android 13 themed icon (alpha only)
  android/app/src/main/res/mipmap-*/ic_launcher_round.png  legacy round icon
  android/app/src/main/res/drawable-*/ic_stat_notification.png  FCM small icon

flutter_launcher_icons (config in pubspec.yaml) then writes ic_launcher.png,
the adaptive foreground/monochrome drawables and mipmap-anydpi-v26/ic_launcher.xml.
mipmap-anydpi-v26/ic_launcher_round.xml is static and uses the same drawables.

Source: branding/android-adaptive-foreground-1024.png (mark only, no text).
Requires Pillow.
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "branding", "android-adaptive-foreground-1024.png")
OUT = os.path.join(ROOT, "branding", "android")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

BG = (0x13, 0x5C, 0x2A, 255)  # brand green, adaptive background
# Farthest mark pixel from the centre, as a fraction of the 108dp canvas.
# The safe zone is a 66dp circle (radius 0.305); 0.28 leaves a small margin.
MARK_RADIUS = 0.28

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def load_mark():
    """Mark cropped to its opaque pixels, plus the max radius from canvas centre."""
    im = Image.open(SRC).convert("RGBA")
    alpha = im.getchannel("A")
    w, h = im.size
    cx, cy = w / 2, h / 2
    px = alpha.load()
    rmax = 0.0
    for y in range(h):
        for x in range(w):
            if px[x, y] > 8:
                r = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                if r > rmax:
                    rmax = r
    return im, rmax


def scaled_canvas(im, rmax, size, radius_frac):
    """Re-centre the mark on a size x size canvas with the given max radius."""
    scale = (radius_frac * size) / rmax
    big = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(big, ((size - big.width) // 2, (size - big.height) // 2))
    return canvas


def silhouette(im, color=(255, 255, 255)):
    out = Image.new("RGBA", im.size, color + (0,))
    out.putalpha(im.getchannel("A"))
    return out


def main():
    im, rmax = load_mark()
    os.makedirs(OUT, exist_ok=True)

    fg = scaled_canvas(im, rmax, 1024, MARK_RADIUS)
    fg.save(os.path.join(OUT, "ic_launcher_foreground-1024.png"))
    silhouette(fg).save(os.path.join(OUT, "ic_launcher_monochrome-1024.png"))

    # Legacy round icon (API < 26 launchers that ask for roundIcon):
    # what the adaptive icon shows in a circle mask = centre 72dp of 108dp.
    for name, d in DENSITIES.items():
        size = round(48 * d)
        full = round(size * 1.5)
        layer = Image.new("RGBA", (full, full), BG)
        layer.alpha_composite(fg.resize((full, full), Image.LANCZOS))
        off = (full - size) // 2
        crop = layer.crop((off, off, off + size, off + size))
        ss = 8
        mask = Image.new("L", (size * ss, size * ss), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size * ss - 1, size * ss - 1), fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        round_icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        round_icon.paste(crop, (0, 0), mask)
        path = os.path.join(RES, f"mipmap-{name}", "ic_launcher_round.png")
        round_icon.save(path)

    # Notification small icon: white on transparent, 24dp, 1dp padding.
    bbox = im.getchannel("A").getbbox()
    mark = silhouette(im.crop(bbox))
    for name, d in DENSITIES.items():
        size = round(24 * d)
        inner = size - 2 * round(1 * d)
        scale = inner / max(mark.width, mark.height)
        m = mark.resize((max(1, round(mark.width * scale)), max(1, round(mark.height * scale))), Image.LANCZOS)
        canvas = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        canvas.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
        folder = os.path.join(RES, f"drawable-{name}")
        os.makedirs(folder, exist_ok=True)
        canvas.save(os.path.join(folder, "ic_stat_notification.png"))

    print(f"mark radius in source: {rmax:.1f}px of 1024; target {MARK_RADIUS} of canvas")


if __name__ == "__main__":
    main()
