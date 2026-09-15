import math

from hingewave_ref.config import Config, load_config
from hingewave_ref.spring import Spring


def test_config_loads_repo_defaults():
    cfg = load_config()
    assert isinstance(cfg, Config)
    assert cfg.eye_distance == 2.0
    assert cfg.max_blur == 0.036
    assert cfg.laptop.arm_delta == 5.0
    assert cfg.laptop.end_angle == 8.0
    assert cfg.phone.inner.clear_start == 100.0
    assert cfg.phone.cover.frost_end == 26.0


def test_spring_settles_on_step_without_overshoot():
    s = Spring(hz=6.0)
    s.reset(0.0)
    peak = 0.0
    t = 0.0
    while t < 1.0:
        x, _ = s.step(100.0, 0.02)
        peak = max(peak, x)
        t += 0.02
    assert abs(x - 100.0) < 1.0
    assert peak <= 100.0 + 1e-9


def test_spring_is_frame_rate_independent():
    fine = Spring(hz=6.0)
    coarse = Spring(hz=6.0)
    fine.reset(10.0)
    coarse.reset(10.0)
    for _ in range(100):
        x_fine, _ = fine.step(50.0, 0.01)
    x_coarse, _ = coarse.step(50.0, 1.0)
    assert math.isclose(x_fine, x_coarse, abs_tol=1e-6)


def test_spring_reports_velocity_toward_target():
    s = Spring(hz=6.0)
    s.reset(90.0)
    _, v = s.step(0.0, 0.02)
    assert v < 0.0
