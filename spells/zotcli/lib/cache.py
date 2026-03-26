"""
cache.py — local JSON cache for the Zotero collection tree.

Cache file: data/cache.json
Structure:  { "collections": [...], "updated_at": "ISO8601" }

Items are NOT cached globally; they are fetched per-collection on demand.
"""
import json
import os
import sys
from datetime import datetime, timezone

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
CACHE_FILE = os.path.join(SPELL_DIR, "data", "cache.json")


def load_cache():
    """Return cached data dict, or None if missing or unreadable."""
    try:
        with open(CACHE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def save_cache(collections):
    """Write collection tree to cache with current UTC timestamp."""
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    data = {
        "collections": collections,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    with open(CACHE_FILE, "w") as f:
        json.dump(data, f, indent=2)


def is_stale(max_age_seconds=3600):
    """Return True if cache is missing, unreadable, or older than max_age_seconds."""
    cache = load_cache()
    if cache is None or "updated_at" not in cache:
        return True
    try:
        updated = datetime.fromisoformat(cache["updated_at"])
        age = (datetime.now(timezone.utc) - updated).total_seconds()
        return age > max_age_seconds
    except (ValueError, TypeError):
        return True


def invalidate():
    """Delete the cache file."""
    try:
        os.remove(CACHE_FILE)
    except FileNotFoundError:
        pass


def get_collections(fresh=False):
    """
    Return the full collection list, from cache when fresh or from API otherwise.
    Automatically saves the API result to cache.
    """
    if not fresh and not is_stale():
        cached = load_cache()
        if cached and "collections" in cached:
            return cached["collections"]

    # Ensure lib/ is importable regardless of call site
    lib_dir = os.path.dirname(os.path.abspath(__file__))
    if lib_dir not in sys.path:
        sys.path.insert(0, lib_dir)

    from client import get_zotero
    zot = get_zotero()
    print("Fetching collection tree from Zotero API…", file=sys.stderr)
    collections = zot.everything(zot.collections())
    save_cache(collections)
    return collections
