"""Splash timeline for foldables whose hinge sensor only reports detents.

Events come from panel switches, detent changes and the gyroscope; the timeline
turns them into per-frame values the ripple shader consumes. Ports re-implement
this and are checked against the splash-*.json fixtures.

    trigger(t)   movement started: a panel lit up or a detent changed; while the
                 ripple is already travelling it only counts as motion, while
                 holding or draining it starts a fresh ripple
    motion(t)    the phone is still being handled (gyroscope above threshold)
    settle(t)    a fully open or fully closed detent was reached
    frame(t)     -> Output
"""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from .config import Config


@dataclass(frozen=True)
class SplashOutput:
    state: str        # idle, splashing, holding, draining
    age: float        # seconds since the current splash started
    front: float      # ripple front position, 0 at the hinge, 1 at the far edge, keeps growing
    ring: float       # ripple ring amplitude 0..1, fades once the front has passed the far edge
    wet: float        # overall water presence 0..1


IDLE = SplashOutput("idle", 0.0, 0.0, 0.0, 0.0)


class SplashTimeline:
    def __init__(self, cfg: Config):
        self.cfg = cfg.splash
        self.state = "idle"
        self.t0: Optional[float] = None
        self.last_motion: Optional[float] = None
        self.drain_start: Optional[float] = None
        self.forced_drain_at: Optional[float] = None
        self.wet_at_drain = 1.0

    # Events ------------------------------------------------------------------

    def trigger(self, t: float) -> None:
        if self.state == "idle":
            self.state = "splashing"
            self.t0 = t
            self.wet_start = 0.0
        elif self.state in ("holding", "draining"):
            # A new movement: restart the ripple without a pop, water continues from its level.
            self.wet_start = self._wet(t)
            self.state = "splashing"
            self.t0 = t
        self.last_motion = t
        self.drain_start = None
        self.forced_drain_at = None

    def motion(self, t: float) -> None:
        if self.state in ("splashing", "holding"):
            self.last_motion = t

    def settle(self, t: float) -> None:
        if self.state in ("splashing", "holding") and self.t0 is not None:
            # Let the current ripple reach the far edge, then drain.
            self.forced_drain_at = max(t, self.t0 + self.cfg.travel_seconds)

    # Frames ------------------------------------------------------------------

    def frame(self, t: float) -> SplashOutput:
        if self.state == "idle" or self.t0 is None:
            return IDLE
        age = t - self.t0
        front = age / self.cfg.travel_seconds

        if self.state == "splashing" and front >= 1.0:
            self.state = "holding"

        if self.state in ("splashing", "holding"):
            still_for = t - (self.last_motion if self.last_motion is not None else self.t0)
            forced = self.forced_drain_at is not None and t >= self.forced_drain_at
            if still_for >= self.cfg.still_seconds or forced:
                self.state = "draining"
                self.drain_start = t
                self.wet_at_drain = self._rise(age)

        wet = self._wet(t)
        if self.state == "draining" and wet <= 0.0:
            self._reset()
            return IDLE

        ring = math.exp(-max(0.0, front - 1.0) * 2.0)
        return SplashOutput(self.state, age, front, ring, wet)

    # Internals ---------------------------------------------------------------

    wet_start = 0.0

    def _rise(self, age: float) -> float:
        rise = min(1.0, age / self.cfg.rise_seconds)
        return self.wet_start + (1.0 - self.wet_start) * rise

    def _wet(self, t: float) -> float:
        if self.t0 is None:
            return 0.0
        if self.state == "draining" and self.drain_start is not None:
            k = 1.0 - (t - self.drain_start) / self.cfg.drain_seconds
            return max(0.0, self.wet_at_drain * k)
        return self._rise(t - self.t0)

    def _reset(self) -> None:
        self.state = "idle"
        self.t0 = None
        self.last_motion = None
        self.drain_start = None
        self.forced_drain_at = None
        self.wet_start = 0.0
