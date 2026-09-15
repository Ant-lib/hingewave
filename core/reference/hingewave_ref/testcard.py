"""Deterministic 320 by 200 test image with landmarks for golden renders."""
from __future__ import annotations

import numpy as np

WIDTH = 320
HEIGHT = 200


def _hsv_to_rgb(h: np.ndarray, s: float, v: float) -> np.ndarray:
    i = np.floor(h * 6.0).astype(int) % 6
    f = h * 6.0 - np.floor(h * 6.0)
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    r = np.choose(i, [np.full_like(f, v), q, np.full_like(f, p), np.full_like(f, p), t, np.full_like(f, v)])
    g = np.choose(i, [t, np.full_like(f, v), np.full_like(f, v), q, np.full_like(f, p), np.full_like(f, p)])
    b = np.choose(i, [np.full_like(f, p), np.full_like(f, p), t, np.full_like(f, v), np.full_like(f, v), q])
    return np.stack([r, g, b], axis=-1)


def make_test_card() -> np.ndarray:
    """Return an HxWx3 float32 image in [0, 1]."""
    ys, xs = np.mgrid[0:HEIGHT, 0:WIDTH]
    hue = xs / WIDTH
    img = _hsv_to_rgb(hue.astype(np.float64), 0.55, 0.85).astype(np.float32)

    grid = (xs % 20 == 0) | (ys % 20 == 0)
    img[grid] = 0.15

    disc = (xs - 80) ** 2 + (ys - 60) ** 2 <= 18 ** 2
    img[disc] = 1.0

    square = (np.abs(xs - 240) <= 18) & (np.abs(ys - 140) <= 18)
    img[square] = 0.0

    for tx in (40, 120, 200, 280):
        img[HEIGHT - 8:HEIGHT, tx:tx + 3] = 1.0

    return img
