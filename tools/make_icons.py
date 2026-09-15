"""Generates the Hingewave icon for every platform from one drawing.

The mark: a flat panel and a tilted panel either side of a dark hinge line, the
same shapes on every platform. Run from the repository root with the core venv:

    core/.venv/bin/python tools/make_icons.py

Writes:
    macos/Resources/Hingewave.icns          (via iconutil, macOS only)
    windows/Hingewave.App/hingewave.ico
    android/app/src/main/res/mipmap-*/ic_launcher_foreground.png
    docs/assets/icon-256.png
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SS = 4  # supersampling

BACKGROUND_TOP = (26, 38, 115)
BACKGROUND_BOTTOM = (18, 25, 74)
FLAT = (230, 233, 245)
TILTED = (242, 168, 90)
HINGE = (14, 21, 64)


def draw_mark(size: int, with_background: bool, inset: float) -> Image.Image:
    """Draws the mark on a `size` square. `inset` is the fraction of the square kept clear around the mark."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if with_background:
        # Vertical gradient inside a rounded square.
        grad = Image.new("RGBA", (s, s))
        gd = ImageDraw.Draw(grad)
        for y in range(s):
            f = y / (s - 1)
            c = tuple(int(BACKGROUND_TOP[i] * (1 - f) + BACKGROUND_BOTTOM[i] * f) for i in range(3))
            gd.line([(0, y), (s, y)], fill=c + (255,))
        mask = Image.new("L", (s, s), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.225), fill=255)
        img.paste(grad, (0, 0), mask)
        # Soft glow behind the panels.
        glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse([s * 0.15, s * 0.2, s * 0.85, s * 0.85], fill=(255, 210, 150, 60))
        glow = glow.filter(ImageFilter.GaussianBlur(s * 0.08))
        img.alpha_composite(glow)
        d = ImageDraw.Draw(img)

    # Content box after inset.
    lo, hi = s * inset, s * (1 - inset)
    w = hi - lo

    def px(x: float) -> float:
        return lo + x * w

    # Shadow under the panels.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rectangle([px(0.20), px(0.32), px(0.48), px(0.72)], fill=(0, 0, 0, 90))
    sd.polygon([(px(0.52), px(0.32)), (px(0.80), px(0.40)), (px(0.80), px(0.64)), (px(0.52), px(0.72))], fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s * 0.02))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)

    # Flat panel, tilted panel (keystone narrowing away from the hinge), hinge bar.
    d.rounded_rectangle([px(0.20), px(0.30), px(0.48), px(0.70)], radius=int(w * 0.02), fill=FLAT + (255,))
    d.polygon([(px(0.52), px(0.30)), (px(0.80), px(0.38)), (px(0.80), px(0.62)), (px(0.52), px(0.70))], fill=TILTED + (255,))
    d.rounded_rectangle([px(0.475), px(0.275), px(0.525), px(0.725)], radius=int(w * 0.012), fill=HINGE + (255,))

    return img.resize((size, size), Image.LANCZOS)


def write_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)


def main() -> int:
    # macOS: iconset then icns.
    mac = draw_mark(1024, True, 0.0)
    icns = ROOT / "macos" / "Resources" / "Hingewave.icns"
    if shutil.which("iconutil"):
        with tempfile.TemporaryDirectory() as tmp:
            iconset = Path(tmp) / "Hingewave.iconset"
            iconset.mkdir()
            for base in (16, 32, 128, 256, 512):
                write_png(mac.resize((base, base), Image.LANCZOS), iconset / f"icon_{base}x{base}.png")
                write_png(mac.resize((base * 2, base * 2), Image.LANCZOS), iconset / f"icon_{base}x{base}@2x.png")
            icns.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)
            print("wrote", icns.relative_to(ROOT))
    else:
        print("iconutil not available; skipped the icns (run on macOS)")

    # Windows: multi-size ico.
    ico = ROOT / "windows" / "Hingewave.App" / "hingewave.ico"
    mac.save(ico, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote", ico.relative_to(ROOT))

    # Android adaptive icon foreground: 108 dp canvas, mark inside the 66 percent safe zone.
    for density, dp in (("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)):
        size = int(108 * dp)
        fg = draw_mark(size, False, 0.17)
        write_png(fg, ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{density}" / "ic_launcher_foreground.png")
    print("wrote android mipmap foregrounds")

    # README.
    write_png(mac.resize((256, 256), Image.LANCZOS), ROOT / "docs" / "assets" / "icon-256.png")
    print("wrote docs/assets/icon-256.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
