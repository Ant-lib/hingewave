"""Generate golden renders of the test card at known tilt and progress."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

from .config import CORE_DIR, Config, load_config
from .render import render, to_uint8
from .testcard import make_test_card

GOLDEN_DIR = CORE_DIR / "golden"
TEST_CARD = CORE_DIR / "test-card.png"
MIN_PSNR_DB = 28.0

GOLDEN_SET = [
    {"file": "t00-p000.png", "tilt": 0.0, "progress": 0.0},
    {"file": "t15-p020.png", "tilt": 15.0, "progress": 0.2},
    {"file": "t30-p045.png", "tilt": 30.0, "progress": 0.45},
    {"file": "t50-p070.png", "tilt": 50.0, "progress": 0.7},
    {"file": "t75-p095.png", "tilt": 75.0, "progress": 0.95},
]


def save_png(path: Path, img: np.ndarray) -> None:
    Image.fromarray(to_uint8(img), mode="RGB").save(path, format="PNG", optimize=False)


def load_png(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"))


def write_goldens(golden_dir: Path = GOLDEN_DIR, test_card_path: Path = TEST_CARD, cfg: Config | None = None) -> list[Path]:
    cfg = cfg or load_config()
    golden_dir.mkdir(parents=True, exist_ok=True)
    card = make_test_card()
    save_png(test_card_path, card)
    written = [test_card_path]
    for entry in GOLDEN_SET:
        out = render(card, entry["tilt"], entry["progress"], cfg)
        path = golden_dir / entry["file"]
        save_png(path, out)
        written.append(path)
    index = {"width": card.shape[1], "height": card.shape[0], "minPsnrDb": MIN_PSNR_DB, "entries": GOLDEN_SET}
    index_path = golden_dir / "index.json"
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1)
        f.write("\n")
    written.append(index_path)
    return written
