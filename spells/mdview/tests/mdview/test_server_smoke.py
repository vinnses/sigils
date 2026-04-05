from pathlib import Path

from lib.server import AppState


def test_app_state_for_file_target(tmp_path: Path):
    doc = tmp_path / "notes.md"
    doc.write_text("# Notes", encoding="utf-8")
    state = AppState.from_target(doc)
    assert state.target_path == doc
    assert state.root_path == tmp_path
