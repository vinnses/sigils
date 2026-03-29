"""
state.py — navigation state (current collection + item position).
State file: data/state.json
"""
import json
import os
import tempfile

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
STATE_FILE = os.path.join(SPELL_DIR, "data", "state.json")

ROOT = "zot://"

_DEFAULT = {
    "collection_key": None,
    "collection_path": ROOT,
    "item_key": None,
    "item_label": None,
    "previous_collection_key": None,
    "previous_collection_path": None,
    "previous_item_key": None,
}


def read_state():
    """Return state dict. Falls back to root state if file is missing or unreadable."""
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        return {**_DEFAULT, **data}
    except (FileNotFoundError, json.JSONDecodeError):
        return dict(_DEFAULT)


def write_state(**fields):
    """Atomically write navigation state to disk."""
    current = read_state()
    current.update(fields)
    for k, v in _DEFAULT.items():
        current.setdefault(k, v)
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    dir_ = os.path.dirname(STATE_FILE)
    fd, tmp = tempfile.mkstemp(dir=dir_, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(current, f, indent=2)
            f.write("\n")
        os.replace(tmp, STATE_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def reset_state():
    """Write default (root) state atomically."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    dir_ = os.path.dirname(STATE_FILE)
    fd, tmp = tempfile.mkstemp(dir=dir_, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(dict(_DEFAULT), f, indent=2)
            f.write("\n")
        os.replace(tmp, STATE_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def full_path(state):
    """Return display path: 'zot://1.Books' or 'zot://1.Books/jurafsky2026'."""
    base = state.get("collection_path") or ROOT
    item_label = state.get("item_label")
    if item_label:
        return f"{base}/{item_label}"
    return base
