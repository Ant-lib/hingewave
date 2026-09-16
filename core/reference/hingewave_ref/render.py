"""Reference renderer for the fold effect (docs/design.md, section 2).

Hinge along the bottom edge of the image. u runs from 0 at the hinge to 1 at
the top edge, v from 0 at the left to 1 at the right. Images are HxWx3
float arrays in [0, 1].
"""
from __future__ import annotations

import math

import numpy as np

from .config import Config

BLUR_LEVELS = 8


def panel_coords(height: int, width: int) -> tuple[np.ndarray, np.ndarray]:
    ys, xs = np.mgrid[0:height, 0:width]
    u = 1.0 - (ys + 0.5) / height
    v = (xs + 0.5) / width
    return u, v


def perspective_warp(img: np.ndarray, tilt_deg: float, cfg: Config) -> np.ndarray:
    """Project the resting picture onto the tilted panel (section 2.2)."""
    h, w, _ = img.shape
    u, v = panel_coords(h, w)
    tau = math.radians(tilt_deg)
    d = cfg.eye_distance
    dz = u * math.sin(tau)
    t = d / (d - dz)
    u2 = 0.5 + t * (u * math.cos(tau) - 0.5)
    v2 = 0.5 + t * (v - 0.5)
    inside = (u2 >= 0.0) & (u2 <= 1.0) & (v2 >= 0.0) & (v2 <= 1.0)
    sx = v2 * w - 0.5
    sy = (1.0 - u2) * h - 0.5
    out = _bilinear(img, sx, sy)
    out[~inside] = 0.0
    return out


def _bilinear(img: np.ndarray, sx: np.ndarray, sy: np.ndarray) -> np.ndarray:
    h, w, _ = img.shape
    x0 = np.floor(sx).astype(int)
    y0 = np.floor(sy).astype(int)
    fx = (sx - x0)[..., None]
    fy = (sy - y0)[..., None]
    x1 = np.clip(x0 + 1, 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x0 = np.clip(x0, 0, w - 1)
    y0 = np.clip(y0, 0, h - 1)
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bottom = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return top * (1 - fy) + bottom * fy


def gaussian_blur(img: np.ndarray, sigma: float) -> np.ndarray:
    """Separable Gaussian, truncated at two standard deviations, edge clamped."""
    if sigma <= 0.05:
        return img.copy()
    radius = max(1, int(math.ceil(2.0 * sigma)))
    xs = np.arange(-radius, radius + 1, dtype=np.float64)
    k = np.exp(-0.5 * (xs / sigma) ** 2)
    k /= k.sum()
    padded = np.pad(img, ((radius, radius), (radius, radius), (0, 0)), mode="edge")
    tmp = np.zeros_like(padded)
    for i, wgt in enumerate(k):
        tmp += wgt * np.roll(padded, i - radius, axis=1)
    out = np.zeros_like(padded)
    for i, wgt in enumerate(k):
        out += wgt * np.roll(tmp, i - radius, axis=0)
    return out[radius:-radius, radius:-radius].astype(img.dtype)


def variable_blur(img: np.ndarray, radius_px: np.ndarray, max_radius_px: float) -> np.ndarray:
    """Per-pixel blur radius, built from a pyramid of uniform blurs."""
    if max_radius_px <= 0.05:
        return img.copy()
    levels = [gaussian_blur(img, (max_radius_px * k / BLUR_LEVELS) / 2.0) for k in range(BLUR_LEVELS + 1)]
    f = np.clip(radius_px / max_radius_px, 0.0, 1.0) * BLUR_LEVELS
    k0 = np.clip(np.floor(f).astype(int), 0, BLUR_LEVELS - 1)
    frac = (f - k0)[..., None]
    stack = np.stack(levels, axis=0)
    a = np.take_along_axis(stack, k0[None, ..., None].repeat(3, axis=-1), axis=0)[0]
    b = np.take_along_axis(stack, (k0 + 1)[None, ..., None].repeat(3, axis=-1), axis=0)[0]
    return a * (1 - frac) + b * frac


def darken(img: np.ndarray, progress: float, u: np.ndarray, gain: float) -> np.ndarray:
    k = np.clip(gain * progress * (0.35 + 0.65 * u), 0.0, 1.0)[..., None]
    return img * (1.0 - k)


def render(img: np.ndarray, tilt_deg: float, progress: float, cfg: Config) -> np.ndarray:
    h, w, _ = img.shape
    u, _ = panel_coords(h, w)
    warped = perspective_warp(img, tilt_deg, cfg)
    max_r = cfg.max_blur * h
    # Blur has a floor at the hinge so the panel frosts as one, rather than going
    # dark while staying razor sharp on the rotation axis (docs/design.md 2.3).
    radius = max_r * progress * (cfg.blur_floor + (1.0 - cfg.blur_floor) * u)
    blurred = variable_blur(warped, radius, max_r)
    return np.clip(darken(blurred, progress, u, cfg.darken_gain), 0.0, 1.0)


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    if mse == 0.0:
        return math.inf
    return 10.0 * math.log10(1.0 / mse)


def to_uint8(img: np.ndarray) -> np.ndarray:
    return np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8)


def from_uint8(img: np.ndarray) -> np.ndarray:
    return img.astype(np.float32) / 255.0
