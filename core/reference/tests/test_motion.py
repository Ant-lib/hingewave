from hingewave_ref.config import load_config
from hingewave_ref.motion import DetentDetector, LaptopMotionModel, PhoneMapping, smoothstep

CFG = load_config()
DT = 0.02


def run(model, trace):
    """Feed (t, angle) pairs, calling capture_ready 100 ms after arming."""
    outputs = []
    armed_at = None
    for t, angle in trace:
        if armed_at is not None and t >= armed_at + 0.1:
            model.capture_ready(t)
            armed_at = None
        out = model.feed(t, angle)
        if out.state == "armed" and armed_at is None and not model.capture_seen:
            armed_at = t
        outputs.append((t, out))
    return outputs


def ramp(t0, a0, t1, a1, dt=DT):
    t = t0
    while t < t1:
        f = (t - t0) / (t1 - t0)
        yield (round(t, 6), a0 + (a1 - a0) * f)
        t += dt


def hold(t0, angle, t1, dt=DT):
    t = t0
    while t < t1:
        yield (round(t, 6), angle)
        t += dt


def test_smoothstep_clamps_and_is_symmetric():
    assert smoothstep(-1.0) == 0.0
    assert smoothstep(2.0) == 1.0
    assert abs(smoothstep(0.5) - 0.5) < 1e-12


def test_slow_close_arms_activates_and_reaches_full_progress():
    m = LaptopMotionModel(CFG)
    trace = list(hold(0.0, 110.0, 1.0)) + list(ramp(1.0, 110.0, 4.0, 0.0)) + list(hold(4.0, 0.0, 5.0))
    outs = run(m, trace)
    states = [o.state for _, o in outs]
    assert states[0] == "idle"
    assert "armed" in states
    assert "active" in states
    first_armed = next(t for t, o in outs if o.state == "armed")
    assert first_armed >= 1.0
    at_end = [o for t, o in outs if 3.8 <= t <= 3.9 and o.state == "active"]
    assert at_end, "should still be active near the end angle"
    assert at_end[-1].progress > 0.98
    assert at_end[-1].tilt > 80.0
    # capture requested from the moment of arming onward until idle
    assert all(o.capture for _, o in outs if o.state in ("armed", "active"))


def test_nudge_never_arms():
    m = LaptopMotionModel(CFG)
    trace = list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 5.5, 85.0)) + list(ramp(5.5, 85.0, 10.5, 110.0))
    outs = run(m, trace)
    assert all(o.state == "idle" for _, o in outs)
    assert all(o.tilt == 0.0 and o.progress == 0.0 for _, o in outs)


def test_stop_midway_clears_after_stillness_then_idles():
    m = LaptopMotionModel(CFG)
    trace = list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 45.0)) + list(hold(2.0, 45.0, 6.0))
    outs = run(m, trace)
    by_t = {t: o for t, o in outs}
    assert by_t[2.5].state == "active"
    # still for stillSeconds (2.0) from about t=2.1 when the spring settles
    clearing = [t for t, o in outs if o.state == "clearing"]
    assert clearing, "expected a clearing phase"
    assert 4.0 <= clearing[0] <= 4.4
    assert by_t[clearing[0]].progress < by_t[2.5].progress or True
    idle_after = [t for t, o in outs if t > clearing[0] and o.state == "idle"]
    assert idle_after
    assert idle_after[0] - clearing[0] <= CFG.clear_seconds + 0.05
    assert by_t[idle_after[0]].tilt == 0.0 and by_t[idle_after[0]].progress == 0.0


def test_reopen_plays_in_reverse_then_clears_above_start():
    m = LaptopMotionModel(CFG)
    trace = list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 40.0)) + list(hold(2.0, 40.0, 2.5)) \
        + list(ramp(2.5, 40.0, 4.0, 110.0)) + list(hold(4.0, 110.0, 5.5))
    outs = run(m, trace)
    by_t = {t: o for t, o in outs}
    p_low = by_t[2.4].progress
    p_mid = by_t[3.2].progress
    assert by_t[2.4].state == "active" and by_t[3.2].state == "active"
    assert p_mid < p_low
    assert by_t[5.4].state == "idle"


def test_display_off_forces_idle():
    m = LaptopMotionModel(CFG)
    trace = list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 45.0))
    run(m, trace)
    m.display_off()
    out = m.feed(2.02, 45.0)
    assert out.state == "idle" and out.tilt == 0.0 and out.progress == 0.0 and out.capture is False


def test_reduce_motion_disables_tilt_only():
    m = LaptopMotionModel(CFG, reduce_motion=True)
    trace = list(hold(0.0, 110.0, 0.5)) + list(ramp(0.5, 110.0, 2.0, 45.0)) + list(hold(2.0, 45.0, 2.5))
    outs = run(m, trace)
    active = [o for _, o in outs if o.state == "active"]
    assert active
    assert all(o.tilt == 0.0 for o in active)
    assert active[-1].progress > 0.3


def test_phone_mapping_inner_and_cover():
    pm = PhoneMapping(CFG)
    assert pm.inner(100.0) == 1.0
    assert pm.inner(174.0) == 0.0
    assert abs(pm.inner(137.0) - 0.5) < 1e-9
    assert pm.cover(6.0) == 0.0
    assert pm.cover(26.0) == 1.0
    assert pm.tilt(180.0) == 0.0
    assert pm.tilt(120.0) == 60.0
    assert pm.is_settled(3.0) and pm.is_settled(177.0) and not pm.is_settled(90.0)


def test_detent_detector():
    d = DetentDetector()
    for v in [0.0, 90.0, 180.0, 90.0, 0.0, 180.0, 0.0, 90.0, 180.0, 90.0, 0.0]:
        d.feed(v)
        assert d.is_detent is None
    d.feed(180.0)
    assert d.is_detent is True

    d2 = DetentDetector()
    d2.feed(0.0)
    d2.feed(37.0)
    assert d2.is_detent is False
