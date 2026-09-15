from hingewave_ref.config import load_config
from hingewave_ref.splash import SplashTimeline

CFG = load_config()


def test_config_has_splash_section():
    assert CFG.splash.travel_seconds == 1.2
    assert CFG.splash.still_seconds == 5.0


def test_idle_until_triggered():
    s = SplashTimeline(CFG)
    assert s.frame(0.0).state == "idle"
    assert s.frame(3.0).wet == 0.0


def test_trigger_rises_travels_then_holds():
    s = SplashTimeline(CFG)
    s.trigger(1.0)
    early = s.frame(1.1)
    assert early.state == "splashing"
    assert 0.3 < early.wet < 0.5          # rising over 0.25 s
    mid = s.frame(1.6)
    assert mid.wet == 1.0
    assert abs(mid.front - 0.5) < 1e-9
    assert mid.ring == 1.0
    held = s.frame(2.5)
    assert held.state == "holding"
    assert held.front > 1.0 and held.ring < 1.0


def test_stillness_drains_after_five_seconds():
    s = SplashTimeline(CFG)
    s.trigger(0.0)
    assert s.frame(4.9).state == "holding"
    d = s.frame(5.0)
    assert d.state == "draining"
    assert d.wet == 1.0
    later = s.frame(5.75)
    assert later.state == "draining" and abs(later.wet - 0.5) < 1e-9
    assert s.frame(6.6).state == "idle"


def test_motion_postpones_the_drain():
    s = SplashTimeline(CFG)
    s.trigger(0.0)
    s.motion(4.0)
    assert s.frame(6.0).state == "holding"
    assert s.frame(9.0).state == "draining"


def test_settle_drains_after_the_ripple_finishes():
    s = SplashTimeline(CFG)
    s.trigger(0.0)
    s.settle(0.5)
    assert s.frame(1.0).state == "splashing"
    assert s.frame(1.2).state == "draining"


def test_retrigger_while_draining_keeps_water_level():
    s = SplashTimeline(CFG)
    s.trigger(0.0)
    s.frame(6.0)                         # begins draining at 5 s of stillness
    mid = s.frame(6.75)                  # half drained
    assert abs(mid.wet - 0.5) < 1e-9
    s.trigger(6.75)
    again = s.frame(6.76)
    assert again.state == "splashing"
    assert again.wet >= 0.5              # no pop back to zero
    assert again.front < 0.05
