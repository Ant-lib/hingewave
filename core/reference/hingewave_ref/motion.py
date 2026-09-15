"""Motion model: raw hinge angles in, (state, tilt, progress, capture) out.

This is the specification in executable form (docs/design.md, section 3).
Ports re-implement it in their own language and are checked against the
fixtures this module generates.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .config import Config
from .spring import Spring

STILL_SPEED = 2.0        # degrees per second, below this the lid counts as still
END_MARGIN = 2.0         # degrees above endAngle required before a stillness clear
REOPEN_MARGIN = 2.0      # within this many degrees of the rest angle counts as reopened
DETENT_SAMPLES = 12      # sensor events needed to decide detent-only
DETENT_VALUES = (0.0, 90.0, 180.0)


def smoothstep(x: float) -> float:
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    return x * x * (3.0 - 2.0 * x)


@dataclass(frozen=True)
class Output:
    state: str          # idle, armed, active, clearing
    tilt: float         # degrees the panel has rotated away from the resting plane
    progress: float     # 0 open, 1 fully folded
    capture: bool       # host should be capturing the screen


IDLE = Output("idle", 0.0, 0.0, False)


class LaptopMotionModel:
    def __init__(self, cfg: Config, reduce_motion: bool = False):
        self.cfg = cfg
        self.reduce_motion = reduce_motion
        self.spring = Spring(cfg.spring_hz)
        self.state = "idle"
        self.last_t: Optional[float] = None
        self.still_since: Optional[float] = None
        self.clear_started: Optional[float] = None
        self.capture_seen = False
        # Angle the lid rests at. Follows the lid whenever it has been still for
        # rest_seconds while idle, so the effect starts from wherever the lid was.
        self.rest_angle: Optional[float] = None
        self.rest_still_since: Optional[float] = None

    # Host events -----------------------------------------------------------

    def capture_ready(self, t: float) -> None:
        self.capture_seen = True
        if self.state == "armed":
            self.state = "active"

    def display_off(self) -> None:
        self._go_idle()

    # Sampling ---------------------------------------------------------------

    def feed(self, t: float, angle: float) -> Output:
        if self.last_t is None:
            self.spring.reset(angle)
            x, v = angle, 0.0
        else:
            x, v = self.spring.step(angle, t - self.last_t)
        self.last_t = t

        lp = self.cfg.laptop

        if self.state == "idle":
            if self.rest_angle is None:
                self.rest_angle = x
            if abs(v) < STILL_SPEED:
                if self.rest_still_since is None:
                    self.rest_still_since = t
                elif t - self.rest_still_since >= lp.rest_seconds:
                    self.rest_angle = x
            else:
                self.rest_still_since = None
            if self.rest_angle - x >= lp.arm_delta and v <= -lp.arm_velocity:
                self.state = "armed"
                self.capture_seen = False
                self.still_since = None

        if self.state in ("armed", "active"):
            if self.rest_angle is not None and x > self.rest_angle - REOPEN_MARGIN:
                self._begin_clearing(t)
            elif abs(v) < STILL_SPEED and x > lp.end_angle + END_MARGIN:
                if self.still_since is None:
                    self.still_since = t
                elif t - self.still_since >= self.cfg.still_seconds:
                    self._begin_clearing(t)
            else:
                self.still_since = None

        if self.state == "idle":
            return IDLE

        tilt, progress = self._shape(x)

        if self.state == "clearing":
            k = 1.0 - (t - self.clear_started) / self.cfg.clear_seconds
            if k <= 0.0:
                self._go_idle()
                return IDLE
            tilt *= k
            progress *= k

        return Output(self.state, tilt, progress, True)

    # Internals --------------------------------------------------------------

    def _shape(self, x: float) -> tuple[float, float]:
        lp = self.cfg.laptop
        rest = self.rest_angle if self.rest_angle is not None else x
        tilt = max(0.0, rest - x)
        progress = smoothstep((rest - x) / max(rest - lp.end_angle, 1e-6))
        if self.reduce_motion:
            tilt = 0.0
        return tilt, progress

    def _begin_clearing(self, t: float) -> None:
        if self.state != "clearing":
            self.state = "clearing"
            self.clear_started = t
            self.still_since = None

    def _go_idle(self) -> None:
        self.state = "idle"
        self.still_since = None
        self.clear_started = None
        self.capture_seen = False
        # Re-anchor at the current angle so a fresh close starts from here.
        self.rest_angle = None
        self.rest_still_since = None


class PhoneMapping:
    """Stateless angle to progress mapping for foldables (section 3.3)."""

    def __init__(self, cfg: Config):
        self.cfg = cfg

    def inner(self, angle: float) -> float:
        c = self.cfg.phone.inner
        return 1.0 - smoothstep((angle - c.clear_start) / (c.clear_end - c.clear_start))

    def cover(self, angle: float) -> float:
        c = self.cfg.phone.cover
        return smoothstep((angle - c.frost_start) / (c.frost_end - c.frost_start))

    def tilt(self, angle: float) -> float:
        return max(0.0, 180.0 - angle)

    def is_settled(self, angle: float) -> bool:
        dz = self.cfg.phone.dead_zone
        return angle <= dz or angle >= 180.0 - dz


class DetentDetector:
    """Decides whether a hinge sensor only reports 0, 90 and 180."""

    def __init__(self):
        self.count = 0
        self.is_detent: Optional[bool] = None

    def feed(self, value: float) -> None:
        if self.is_detent is not None:
            return
        if value not in DETENT_VALUES:
            self.is_detent = False
            return
        self.count += 1
        if self.count >= DETENT_SAMPLES:
            self.is_detent = True
