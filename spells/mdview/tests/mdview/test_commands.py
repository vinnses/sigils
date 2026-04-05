from lib.commands import normalize_argv, parse_args
from lib.commands import resolve_cli_target


def test_alias_invocation_becomes_serve():
    args = parse_args(normalize_argv(["notes.md"]))
    assert args.command == "serve"
    assert args.path == "notes.md"


def test_list_is_not_treated_as_a_path():
    args = parse_args(normalize_argv(["list"]))
    assert args.command == "list"


def test_background_is_only_valid_for_serve():
    args = parse_args(normalize_argv(["serve", "notes.md", "--background"]))
    assert args.background is True


def test_default_path_is_current_directory():
    args = parse_args(normalize_argv(["serve"]))
    assert args.path == "."


def test_resolve_cli_target_uses_invocation_directory(tmp_path, monkeypatch):
    docs = tmp_path / "docs"
    docs.mkdir()
    note = docs / "note.md"
    note.write_text("# hi", encoding="utf-8")
    monkeypatch.setenv("MDVIEW_CALLER_CWD", str(docs))
    resolved = resolve_cli_target("note.md")
    assert resolved == note.resolve()
