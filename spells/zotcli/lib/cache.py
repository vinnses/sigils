"""
cache.py — local JSON cache for Zotero collections and items.

Cache file: data/cache.json
Structure:  { "collections": [...], "items": [...], "updated_at": "ISO8601" }
"""
import json
import os
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


def save_cache(collections, items):
    """Write collections and items to cache with current UTC timestamp."""
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    data = {
        "collections": collections,
        "items": items,
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
