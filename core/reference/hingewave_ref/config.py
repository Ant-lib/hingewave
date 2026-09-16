"""Load core/effect.json into typed dataclasses.

The JSON file is the single place where the effect is tuned. Every port
bundles or mirrors it and proves parity with a test.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

CORE_DIR = Path(__file__).resolve().parents[2]
EFFECT_JSON = CORE_DIR / "effect.json"


@dataclass(frozen=True)
class LaptopConfig:
    arm_delta: float
    rest_seconds: float
    end_angle: float
    arm_velocity: float


@dataclass(frozen=True)
class InnerConfig:
    clear_start: float
    clear_end: float


@dataclass(frozen=True)
class CoverConfig:
    frost_start: float
    frost_end: float


@dataclass(frozen=True)
class PhoneConfig:
    dead_zone: float
    inner: InnerConfig
    cover: CoverConfig


@dataclass(frozen=True)
class SplashConfig:
    travel_seconds: float
    rise_seconds: float
    still_seconds: float
    drain_seconds: float
    swell_hz: float
    motion_threshold: float


@dataclass(frozen=True)
class Config:
    eye_distance: float
    max_blur: float
    blur_floor: float
    darken_gain: float
    spring_hz: float
    still_seconds: float
    clear_seconds: float
    laptop: LaptopConfig
    phone: PhoneConfig
    splash: SplashConfig


def config_from_dict(d: dict) -> Config:
    lp = d["laptop"]
    ph = d["phone"]
    sp = d["splash"]
    return Config(
        eye_distance=float(d["eyeDistance"]),
        max_blur=float(d["maxBlur"]),
        blur_floor=float(d["blurFloor"]),
        darken_gain=float(d["darkenGain"]),
        spring_hz=float(d["springHz"]),
        still_seconds=float(d["stillSeconds"]),
        clear_seconds=float(d["clearSeconds"]),
        laptop=LaptopConfig(
            arm_delta=float(lp["armDelta"]),
            rest_seconds=float(lp["restSeconds"]),
            end_angle=float(lp["endAngle"]),
            arm_velocity=float(lp["armVelocity"]),
        ),
        phone=PhoneConfig(
            dead_zone=float(ph["deadZone"]),
            inner=InnerConfig(
                clear_start=float(ph["inner"]["clearStart"]),
                clear_end=float(ph["inner"]["clearEnd"]),
            ),
            cover=CoverConfig(
                frost_start=float(ph["cover"]["frostStart"]),
                frost_end=float(ph["cover"]["frostEnd"]),
            ),
        ),
        splash=SplashConfig(
            travel_seconds=float(sp["travelSeconds"]),
            rise_seconds=float(sp["riseSeconds"]),
            still_seconds=float(sp["stillSeconds"]),
            drain_seconds=float(sp["drainSeconds"]),
            swell_hz=float(sp["swellHz"]),
            motion_threshold=float(sp["motionThreshold"]),
        ),
    )


def load_config(path: Path = EFFECT_JSON) -> Config:
    with open(path, "r", encoding="utf-8") as f:
        return config_from_dict(json.load(f))
