#!/usr/bin/env python3
"""Render the README demo assets through the reference implementation.

    python3 tools/make_demo.py --desktop path/to/desktop.png

Writes docs/assets/fold-demo.gif (a close and reopen at 12.5 frames a second)
and docs/assets/fold-frames.png (the same desktop at four lid angles). The
desktop picture is supplied on the command line rather than committed, so the
repository carries no wallpaper artwork.

Both assets come from core/reference, so they always show the effect as
core/effect.json currently defines it. Regenerate them after changing it.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "core" / "reference"))

from hingewave_ref.config import load_config  # noqa: E402
from hingewave_ref.motion import LaptopMotionModel  # noqa: E402
from hingewave_ref.render import from_uint8, render, to_uint8  # noqa: E402

GIF_SIZE = (520, 325)
PANEL_SIZE = (320, 200)
PANEL_GAP = 6
STRIP_ANGLES = [105.0, 82.0, 58.0, 35.0]
REST_ANGLE = 105.0
STEP = 0.02          # seconds between model updates
FRAME_EVERY = 4      # every fourth update becomes a GIF frame, so 80 ms
FIRST_HOLD_MS = 660
LAST_HOLD_MS = 240


def load_desktop(path: Path, size: tuple[int, int]) -> np.ndarray:
    img = Image.open(path).convert("RGB")
    target = size[0] / size[1]
    w, h = img.size
    if w / h > target:                      # too wide, trim the sides
        new_w = int(round(h * target))
        img = img.crop(((w - new_w) // 2, 0, (w - new_w) // 2 + new_w, h))
    else:                                   # too tall, trim the top
        new_h = int(round(w / target))
        img = img.crop((0, h - new_h, w, h))
    return from_uint8(np.asarray(img.resize(size, Image.LANCZOS)))


def angle_track() -> list[float]:
    """Rest at 105, close to 10 over 1.1 s, pause, reopen, rest again."""
    track: list[float] = []

    def hold(seconds: float, angle: float) -> None:
        track.extend([angle] * int(round(seconds / STEP)))

    def sweep(seconds: float, start: float, end: float) -> None:
        n = int(round(seconds / STEP))
        track.extend(start + (end - start) * (i + 1) / n for i in range(n))

    hold(0.4, REST_ANGLE)
    sweep(1.1, REST_ANGLE, 10.0)
    hold(0.24, 10.0)
    sweep(1.0, 10.0, REST_ANGLE)
    hold(0.4, REST_ANGLE)
    return track


def make_gif(desktop: np.ndarray, out: Path) -> None:
    cfg = load_config()
    model = LaptopMotionModel(cfg)
    frames: list[Image.Image] = []
    for i, angle in enumerate(angle_track()):
        out_state = model.feed(i * STEP, angle)
        if out_state.state == "armed":
            model.capture_ready(i * STEP)
        if i % FRAME_EVERY:
            continue
        pic = render(desktop, out_state.tilt, out_state.progress, cfg)
        frames.append(Image.fromarray(to_uint8(pic)))

    durations = [80] * len(frames)
    durations[0] = FIRST_HOLD_MS
    durations[-1] = LAST_HOLD_MS
    frames[0].save(
        out,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
    )
    print(f"wrote {out} ({len(frames)} frames)")


def make_strip(desktop_full: np.ndarray, out: Path) -> None:
    cfg = load_config()
    panels = []
    for angle in STRIP_ANGLES:
        tilt = max(0.0, REST_ANGLE - angle)
        span = max(REST_ANGLE - cfg.laptop.end_angle, 1e-6)
        x = min(max(tilt / span, 0.0), 1.0)
        progress = x * x * (3.0 - 2.0 * x)
        pic = render(desktop_full, tilt, progress, cfg)
        panels.append(Image.fromarray(to_uint8(pic)).resize(PANEL_SIZE, Image.LANCZOS))

    w = PANEL_SIZE[0] * len(panels) + PANEL_GAP * (len(panels) - 1)
    strip = Image.new("RGB", (w, PANEL_SIZE[1]), (0, 0, 0))
    for i, panel in enumerate(panels):
        strip.paste(panel, (i * (PANEL_SIZE[0] + PANEL_GAP), 0))
    strip.save(out)
    print(f"wrote {out} (angles {', '.join(f'{a:g}' for a in STRIP_ANGLES)} degrees)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--desktop", required=True, type=Path, help="desktop picture to fold")
    ap.add_argument("--out", type=Path, default=ROOT / "docs" / "assets")
    args = ap.parse_args()

    make_gif(load_desktop(args.desktop, GIF_SIZE), args.out / "fold-demo.gif")
    make_strip(load_desktop(args.desktop, (960, 600)), args.out / "fold-frames.png")


if __name__ == "__main__":
    main()
