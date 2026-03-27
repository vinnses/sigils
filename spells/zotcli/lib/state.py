"""
state.py — navigation state (current collection position).
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

_DEFAULT = {
    "collection_key": None,
    "path": "~",
    "previous_key": None,
    "previous_path": None,
}


def read_state():
    """Return state dict. Falls back to root state if file is missing or unreadable."""
    try:
        with open(STATE_FILE) as f:
            data = json.load(f)
        return {**_DEFAULT, **data}
    except (FileNotFoundError, json.JSONDecodeError):
        return dict(_DEFAULT)


def write_state(collection_key, path, previous_key=None, previous_path=None):
    """Atomically write navigation state to disk."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    data = {
        "collection_key": collection_key,
        "path": path,
        "previous_key": previous_key,
        "previous_path": previous_path,
    }
    dir_ = os.path.dirname(STATE_FILE)
    fd, tmp = tempfile.mkstemp(dir=dir_, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp, STATE_FILE)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
