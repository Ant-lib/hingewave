import math

import numpy as np

from hingewave_ref.config import load_config
from hingewave_ref.render import panel_coords, perspective_warp, psnr, render
from hingewave_ref.testcard import HEIGHT, WIDTH, make_test_card

CFG = load_config()


def test_test_card_shape_and_landmarks():
    card = make_test_card()
    assert card.shape == (HEIGHT, WIDTH, 3)
    assert card.dtype == np.float32
    assert np.all(card[60, 80] == 1.0)       # white disc centre
    assert np.all(card[140, 240] == 0.0)     # black square centre
    assert np.all(card[HEIGHT - 1, 41] == 1.0)  # hinge tick


def test_identity_at_rest():
    card = make_test_card()
    out = render(card, 0.0, 0.0, CFG)
    assert psnr(out, card) > 60.0


def test_hinge_row_is_unchanged_by_tilt():
    card = make_test_card()
    warped = perspective_warp(card, 30.0, CFG)
    assert psnr(warped[-1], card[-1]) > 40.0


def test_tilt_narrows_content_away_from_hinge():
    card = make_test_card()
    warped = perspective_warp(card, 40.0, CFG)
    # far corners map outside the resting picture and go black
    assert np.all(warped[0, 0] == 0.0) and np.all(warped[0, -1] == 0.0)
    # centre column near the top still shows content
    assert warped[5, WIDTH // 2].max() > 0.1


def test_full_progress_darkens_far_edge():
    card = make_test_card()
    out = render(card, 0.0, 1.0, CFG)
    assert out[0:5].max() < 0.02
    # hinge edge only partly darkened
    u, _ = panel_coords(HEIGHT, WIDTH)
    assert out[-1].mean() > 0.05


def test_blur_grows_with_distance_from_hinge():
    card = make_test_card()
    out = render(card, 0.0, 1.0, CFG)
    # the grid line contrast should be much lower near the top than near the hinge
    top = out[20:40, :, 0]
    near = out[HEIGHT - 40:HEIGHT - 20, :, 0]
    assert top.std() < near.std()


def test_psnr_identity_is_infinite():
    a = np.zeros((4, 4, 3))
    assert math.isinf(psnr(a, a))
