"""Command line: `python -m hingewave_ref regen` or `check`.

regen writes core/test-card.png, core/fixtures/*.json and core/golden/* from
the reference implementation. check regenerates into a temporary directory
and fails if anything committed differs, so CI catches stale files.
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

import numpy as np

from .config import CORE_DIR
from .fixtures import FIXTURES_DIR, write_fixtures
from .goldens import GOLDEN_DIR, TEST_CARD, load_png, write_goldens


def regen() -> int:
    for p in write_fixtures() + write_goldens():
        print(f"wrote {p.relative_to(CORE_DIR)}")
    return 0


def check() -> int:
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        fresh_fixtures = tmp_path / "fixtures"
        fresh_golden = tmp_path / "golden"
        fresh_card = tmp_path / "test-card.png"
        write_fixtures(fresh_fixtures)
        write_goldens(fresh_golden, fresh_card)

        for fresh in sorted(fresh_fixtures.glob("*.json")):
            committed = FIXTURES_DIR / fresh.name
            if not committed.exists():
                problems.append(f"missing fixtures/{fresh.name}")
                continue
            if json.loads(fresh.read_text()) != json.loads(committed.read_text()):
                problems.append(f"stale fixtures/{fresh.name}")
        for committed in sorted(FIXTURES_DIR.glob("*.json")):
            if not (fresh_fixtures / committed.name).exists():
                problems.append(f"orphan fixtures/{committed.name}")

        pairs = [(fresh_card, TEST_CARD)] + [(fresh_golden / p.name, GOLDEN_DIR / p.name) for p in fresh_golden.glob("*.png")]
        for fresh, committed in pairs:
            if not committed.exists():
                problems.append(f"missing {committed.relative_to(CORE_DIR)}")
            elif not np.array_equal(load_png(fresh), load_png(committed)):
                problems.append(f"stale {committed.relative_to(CORE_DIR)}")
        fresh_index = json.loads((fresh_golden / "index.json").read_text())
        committed_index_path = GOLDEN_DIR / "index.json"
        if not committed_index_path.exists() or json.loads(committed_index_path.read_text()) != fresh_index:
            problems.append("stale golden/index.json")

    for p in problems:
        print(p)
    if problems:
        print("run: python -m hingewave_ref regen")
        return 1
    print("core fixtures and goldens are up to date")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "regen":
        return regen()
    if len(argv) == 2 and argv[1] == "check":
        return check()
    print("usage: python -m hingewave_ref [regen|check]")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
