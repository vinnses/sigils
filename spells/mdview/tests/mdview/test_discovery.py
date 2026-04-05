from pathlib import Path

from lib.discovery import directory_contains_markdown, list_directory_view


def test_directory_contains_markdown(tmp_path: Path):
    nested = tmp_path / "nested"
    nested.mkdir()
    (nested / "doc.md").write_text("# hi", encoding="utf-8")
    assert directory_contains_markdown(tmp_path) is True


def test_directory_view_filters_non_markdown(tmp_path: Path):
    (tmp_path / "a.md").write_text("# A", encoding="utf-8")
    (tmp_path / "b.txt").write_text("ignore", encoding="utf-8")
    (tmp_path / "nested").mkdir()
    (tmp_path / "nested" / "c.md").write_text("# C", encoding="utf-8")
    entries = list_directory_view(tmp_path)
    labels = [entry["name"] for entry in entries]
    assert "a.md" in labels
    assert "nested" in labels
    assert "b.txt" not in labels
