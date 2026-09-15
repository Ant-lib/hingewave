"""Critically damped spring with an exact closed-form step.

Used to smooth raw hinge angles. Because the step is exact, the result does
not depend on how often it is called, so 50 Hz polling and 120 Hz rendering
agree. Ports must use the same formula.
"""
from __future__ import annotations

import math


class Spring:
    def __init__(self, hz: float):
        self.omega = 2.0 * math.pi * hz
        self.x = 0.0
        self.v = 0.0

    def reset(self, x: float) -> None:
        self.x = x
        self.v = 0.0

    def step(self, target: float, dt: float) -> tuple[float, float]:
        if dt <= 0.0:
            return self.x, self.v
        w = self.omega
        d = self.x - target
        e = math.exp(-w * dt)
        x_new = target + (d + (self.v + w * d) * dt) * e
        v_new = (self.v - w * (self.v + w * d) * dt) * e
        self.x = x_new
        self.v = v_new
        return self.x, self.v
