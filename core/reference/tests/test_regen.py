import json

from hingewave_ref.__main__ import check
from hingewave_ref.config import CORE_DIR
from hingewave_ref.fixtures import build_fixtures


def test_committed_fixtures_and_goldens_are_current():
    assert check() == 0


def test_fixture_shapes():
    fx = build_fixtures()
    assert set(fx) >= {"laptop-slow-close", "laptop-nudge", "laptop-close-reopen", "laptop-stop-midway",
                       "phone-inner-open", "phone-cover-open", "phone-detent"}
    slow = fx["laptop-slow-close"]
    assert slow["captureLatencyMs"] == 100
    states = {e["state"] for e in slow["expect"]}
    assert {"idle", "active"} <= states
    assert all(e["state"] == "idle" for e in fx["laptop-nudge"]["expect"])
    assert "clearing" in {e["state"] for e in fx["laptop-stop-midway"]["expect"]}


def test_golden_index_lists_files_that_exist():
    index = json.loads((CORE_DIR / "golden" / "index.json").read_text())
    assert index["minPsnrDb"] == 28.0
    for entry in index["entries"]:
        assert (CORE_DIR / "golden" / entry["file"]).exists()
