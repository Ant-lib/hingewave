"""Generate motion-model fixtures that every port must replay."""
from __future__ import annotations

import json
from pathlib import Path

from .config import CORE_DIR, Config, load_config
from .motion import DetentDetector, LaptopMotionModel, PhoneMapping
from .splash import SplashTimeline

FIXTURES_DIR = CORE_DIR / "fixtures"
DT = 0.02
CAPTURE_LATENCY_MS = 100
EXPECT_EVERY = 10
TOLERANCE = {"deg": 0.5, "progress": 0.02}


def ramp(t0: float, a0: float, t1: float, a1: float, dt: float = DT):
    t = t0
    while t < t1 - 1e-9:
        f = (t - t0) / (t1 - t0)
        yield (round(t, 6), round(a0 + (a1 - a0) * f, 6))
        t += dt


def hold(t0: float, angle: float, t1: float, dt: float = DT):
    t = t0
    while t < t1 - 1e-9:
        yield (round(t, 6), float(angle))
        t += dt


def replay_laptop(cfg: Config, samples, reduce_motion: bool = False, latency_ms: int = CAPTURE_LATENCY_MS):
    """Run the model the way a host would: capture_ready fires latency after arming."""
    model = LaptopMotionModel(cfg, reduce_motion=reduce_motion)
    armed_at = None
    outputs = []
    for t, angle in samples:
        if armed_at is not None and t >= armed_at + latency_ms / 1000.0:
            model.capture_ready(t)
            armed_at = None
        out = model.feed(t, angle)
        if out.state == "armed" and armed_at is None and not model.capture_seen:
            armed_at = t
        outputs.append((t, out))
    return outputs


LAPTOP_TRACES = {
    "laptop-slow-close": lambda: list(hold(0.0, 110.0, 1.0)) + list(ramp(1.0, 110.0, 4.0, 0.0)) + list(hold(4.0, 0.0, 5.0)),
    "laptop-nudge": lambda: list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 5.5, 85.0)) + list(ramp(5.5, 85.0, 10.5, 110.0)),
    "laptop-close-reopen": lambda: list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 40.0)) + list(hold(2.0, 40.0, 2.5))
    + list(ramp(2.5, 40.0, 4.0, 110.0)) + list(hold(4.0, 110.0, 5.5)),
    "laptop-stop-midway": lambda: list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 45.0)) + list(hold(2.0, 45.0, 6.0)),
    "laptop-fast-flick": lambda: list(hold(0.0, 120.0, 0.3)) + list(ramp(0.3, 120.0, 0.8, 0.0)) + list(hold(0.8, 0.0, 1.5)),
}

PHONE_TRACES = {
    "phone-inner-open": ("inner", lambda: list(ramp(0.0, 90.0, 1.0, 180.0)) + list(hold(1.0, 180.0, 1.5))),
    "phone-cover-open": ("cover", lambda: list(ramp(0.0, 0.0, 1.0, 40.0)) + list(hold(1.0, 40.0, 1.3))),
}

DETENT_TRACES = {
    "phone-detent": ([0.0, 90.0, 180.0, 90.0, 0.0, 180.0, 0.0, 90.0, 180.0, 90.0, 0.0, 180.0], True),
    "phone-continuous": ([0.0, 3.0, 7.0, 12.0], False),
}


# Splash timelines: a list of (t, event) and the frame times to check.
SPLASH_TRACES = {
    "splash-open-and-hold": ([(0.5, "trigger"), (2.0, "motion"), (3.0, "motion")], [0.0, 0.6, 1.0, 1.7, 2.5, 4.0, 7.9, 8.1, 8.8, 9.7]),
    "splash-open-to-flat": ([(0.0, "trigger"), (0.4, "settle")], [0.2, 0.8, 1.19, 1.25, 2.0, 2.8]),
    "splash-retrigger-while-draining": ([(0.0, "trigger"), (5.75, "trigger")], [4.9, 5.2, 5.75, 5.8, 6.5, 11.0, 12.5]),
}


def build_splash_fixtures(cfg: Config) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for name, (events, frames) in SPLASH_TRACES.items():
        tl = SplashTimeline(cfg)
        pending = sorted(events)
        expect = []
        for t in sorted(frames):
            while pending and pending[0][0] <= t:
                et, kind = pending.pop(0)
                getattr(tl, kind)(et)
            o = tl.frame(t)
            expect.append({"t": t, "state": o.state, "front": round(o.front, 4), "ring": round(o.ring, 4), "wet": round(o.wet, 4)})
        out[name] = {
            "platform": "splash",
            "events": [{"t": t, "kind": k} for t, k in events],
            "expect": expect,
            "tolerance": {"value": 0.02},
        }
    return out


def build_fixtures(cfg: Config | None = None) -> dict[str, dict]:
    cfg = cfg or load_config()
    out: dict[str, dict] = {}
    for name, make in LAPTOP_TRACES.items():
        samples = make()
        replayed = replay_laptop(cfg, samples)
        expect = [
            {"t": t, "state": o.state, "tilt": round(o.tilt, 4), "progress": round(o.progress, 4), "capture": o.capture}
            for i, (t, o) in enumerate(replayed) if i % EXPECT_EVERY == 0
        ]
        out[name] = {
            "platform": "laptop",
            "captureLatencyMs": CAPTURE_LATENCY_MS,
            "reduceMotion": False,
            "samples": [[t, a] for t, a in samples],
            "expect": expect,
            "tolerance": TOLERANCE,
        }
    pm = PhoneMapping(cfg)
    for name, (panel, make) in PHONE_TRACES.items():
        samples = make()
        fn = pm.inner if panel == "inner" else pm.cover
        expect = [
            {"t": t, "progress": round(fn(a), 4), "tilt": round(pm.tilt(a), 4), "settled": pm.is_settled(a)}
            for i, (t, a) in enumerate(samples) if i % EXPECT_EVERY == 0
        ]
        out[name] = {
            "platform": "phone",
            "panel": panel,
            "samples": [[t, a] for t, a in samples],
            "expect": expect,
            "tolerance": TOLERANCE,
        }
    for name, (values, expected) in DETENT_TRACES.items():
        d = DetentDetector()
        for v in values:
            d.feed(v)
        assert d.is_detent is expected, name
        out[name] = {"platform": "phone-detent", "values": values, "expectDetent": expected}
    out.update(build_splash_fixtures(cfg))
    return out


def write_fixtures(directory: Path = FIXTURES_DIR, cfg: Config | None = None) -> list[Path]:
    directory.mkdir(parents=True, exist_ok=True)
    written = []
    for name, data in build_fixtures(cfg).items():
        path = directory / f"{name}.json"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1)
            f.write("\n")
        written.append(path)
    return written
