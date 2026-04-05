from pathlib import Path


ASSET_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}


def is_markdown(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() == ".md"


def directory_contains_markdown(path: Path) -> bool:
    for child in path.rglob("*.md"):
        if child.is_file():
            return True
    return False


def list_directory_view(path: Path) -> list[dict]:
    entries = []
    for child in path.iterdir():
        if child.is_dir():
            if directory_contains_markdown(child):
                entries.append({"name": child.name, "path": child, "kind": "directory"})
        elif is_markdown(child):
            entries.append({"name": child.name, "path": child, "kind": "markdown"})

    return sorted(entries, key=lambda item: (item["kind"] != "directory", item["name"].lower()))


def resolve_target_path(root_path: Path, request_path: str) -> Path:
    relative = request_path.lstrip("/")
    candidate = (root_path / relative).resolve()
    if root_path.resolve() not in {candidate, *candidate.parents}:
        raise ValueError("requested path escapes served root")
    return candidate


def classify_target(target: Path) -> str:
    if target.is_dir():
        return "directory"
    if is_markdown(target):
        return "markdown"
    if target.is_file() and target.suffix.lower() in ASSET_SUFFIXES:
        return "asset"
    raise FileNotFoundError(target)
