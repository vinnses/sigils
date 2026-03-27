#!/usr/bin/env python3
"""
smoke.py — v3 smoke tests for zotcli.
All tests use temp files. Never pollutes data/ or config/.
"""
import json
import os
import sys
import tempfile

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

passed = 0
failed = 0


def check(label, fn):
    global passed, failed
    try:
        fn()
        print(f"[pass] {label}")
        passed += 1
    except Exception as e:
        print(f"[fail] {label}: {e}")
        import traceback
        traceback.print_exc()
        failed += 1


# ---------------------------------------------------------------------------
# 1. Module imports
# ---------------------------------------------------------------------------

check("cache.py imports",      lambda: __import__("cache"))
check("state.py imports",      lambda: __import__("state"))
check("navigator.py imports",  lambda: __import__("navigator"))
check("formatters.py imports", lambda: __import__("formatters"))
check("config.py imports",     lambda: __import__("config"))
check("finder.py imports",     lambda: __import__("finder"))

# client.py requires pyzotero
try:
    import client  # noqa: F401
    print("[pass] client.py imports")
    passed += 1
except SystemExit:
    print("[pass] client.py: loaded (no credentials — expected)")
    passed += 1
except ImportError as e:
    print(f"[skip] client.py: pyzotero not installed ({e})")

# ---------------------------------------------------------------------------
# 2. state.py — round-trip with item_key fields
# ---------------------------------------------------------------------------

import state

def test_state_paths():
    assert "state.json" in state.STATE_FILE

check("state.STATE_FILE resolves correctly", test_state_paths)


def test_state_roundtrip():
    orig = state.STATE_FILE
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name
    state.STATE_FILE = tmp_path
    try:
        state.write_state(
            collection_key="KEY1",
            collection_path="^/Books",
            item_key="ITEM1",
            item_label="jurafsky2026",
            previous_collection_key="KEY0",
            previous_collection_path="^",
            previous_item_key=None,
        )
        s = state.read_state()
        assert s["collection_key"] == "KEY1", f"got {s['collection_key']!r}"
        assert s["collection_path"] == "^/Books", f"got {s['collection_path']!r}"
        assert s["item_key"] == "ITEM1", f"got {s['item_key']!r}"
        assert s["item_label"] == "jurafsky2026", f"got {s['item_label']!r}"
        assert s["previous_collection_key"] == "KEY0"

        # full_path with item
        assert state.full_path(s) == "^/Books/jurafsky2026", f"got {state.full_path(s)!r}"

        # reset
        state.reset_state()
        s2 = state.read_state()
        assert s2["collection_key"] is None
        assert s2["collection_path"] == "^"
        assert s2["item_key"] is None
        assert state.full_path(s2) == "^"
    finally:
        state.STATE_FILE = orig
        try: os.unlink(tmp_path)
        except OSError: pass

check("state read/write round-trip with item_key", test_state_roundtrip)

# ---------------------------------------------------------------------------
# 3. navigator.py — ^, .., -, absolute, relative, item entry, item exit
# ---------------------------------------------------------------------------

import navigator as nav

cols = [
    {"data": {"key": "ROOT1", "name": "Papers",   "parentCollection": False}},
    {"data": {"key": "ROOT2", "name": "Books",    "parentCollection": False}},
    {"data": {"key": "CHILD1","name": "NLP",      "parentCollection": "ROOT1"}},
]

items = [
    {"data": {"key": "ITEM1", "citationKey": "jurafsky2026",
              "title": "Speech and Language Processing", "collections": ["ROOT1"]}},
]


def test_nav_root():
    k, p, ik, il = nav.resolve_path(None, "^", "^", cols)
    assert k is None and p == "^" and ik is None

check("navigator: ^ goes to root", test_nav_root)


def test_nav_relative():
    k, p, ik, il = nav.resolve_path(None, "^", "Papers", cols)
    assert k == "ROOT1" and p == "^/Papers"

check("navigator: relative collection name", test_nav_relative)


def test_nav_dotdot():
    k, p, ik, il = nav.resolve_path("ROOT1", "^/Papers", "..", cols)
    assert k is None and p == "^"

check("navigator: .. from collection", test_nav_dotdot)


def test_nav_absolute():
    k, p, ik, il = nav.resolve_path(None, "^", "^/Papers/NLP", cols)
    assert k == "CHILD1" and p == "^/Papers/NLP"

check("navigator: ^/absolute path", test_nav_absolute)


def test_nav_item_entry():
    k, p, ik, il = nav.resolve_path("ROOT1", "^/Papers", "jurafsky2026", cols,
                                     items=items)
    assert k == "ROOT1"       # collection key unchanged
    assert p == "^/Papers"    # collection path unchanged
    assert ik == "ITEM1"
    assert il == "jurafsky2026"

check("navigator: cd into item", test_nav_item_entry)


def test_nav_item_exit():
    # Inside item, .. should exit item back to collection
    k, p, ik, il = nav.resolve_path("ROOT1", "^/Papers", "..", cols,
                                     item_key="ITEM1")
    assert k == "ROOT1"
    assert p == "^/Papers"
    assert ik is None

check("navigator: .. exits item", test_nav_item_exit)


def test_nav_dash():
    k, p, ik, il = nav.resolve_path(
        "ROOT1", "^/Papers", "-", cols,
        previous_key="ROOT2", previous_path="^/Books", previous_item_key=None
    )
    assert k == "ROOT2" and p == "^/Books"

check("navigator: - goes to previous", test_nav_dash)


def test_nav_build_path():
    p = nav.build_path(cols, "CHILD1")
    assert p == "^/Papers/NLP", f"got {p!r}"
    assert nav.build_path(cols, None) == "^"

check("navigator.build_path", test_nav_build_path)

# ---------------------------------------------------------------------------
# 4. config.py — load defaults, overlay, dot-notation get/set
# ---------------------------------------------------------------------------

import config as _config


def test_config_defaults():
    # Load defaults without a user config
    orig = _config.USER_FILE
    _config.USER_FILE = "/tmp/__zotcli_no_user_config.yaml"
    try:
        cfg = _config.load_config()
        assert _config.get_value(cfg, "ls.default_sort") == "name"
        assert _config.get_value(cfg, "cache.ttl_seconds") == 3600
        assert _config.get_value(cfg, "get.default_format") == "bibtex"
        assert _config.get_value(cfg, "nonexistent.key") is None
    finally:
        _config.USER_FILE = orig

check("config: load defaults and get_value", test_config_defaults)


def test_config_set():
    with tempfile.NamedTemporaryFile(suffix=".yaml", delete=False) as tmp:
        tmp_path = tmp.name
    orig = _config.USER_FILE
    _config.USER_FILE = tmp_path
    try:
        _config.set_value("ls.default_sort", "date")
        cfg = _config.load_config()
        assert _config.get_value(cfg, "ls.default_sort") == "date"
    finally:
        _config.USER_FILE = orig
        try: os.unlink(tmp_path)
        except OSError: pass

check("config: set_value writes to user yaml", test_config_set)


def test_config_deep_merge():
    import config as cfg_mod
    base     = {"a": {"x": 1, "y": 2}, "b": 3}
    override = {"a": {"y": 99, "z": 4}}
    merged   = cfg_mod._deep_merge(base, override)
    assert merged["a"]["x"] == 1
    assert merged["a"]["y"] == 99
    assert merged["a"]["z"] == 4
    assert merged["b"] == 3

check("config: deep merge", test_config_deep_merge)

# ---------------------------------------------------------------------------
# 5. formatters.py — colors, citation key extraction, multi-collection indicator
# ---------------------------------------------------------------------------

import formatters as fmt


def test_fmt_colors():
    for attr in ("BOLD", "DIM", "CYAN", "RED", "NC"):
        assert hasattr(fmt, attr), f"missing {attr}"

check("formatters: color constants present", test_fmt_colors)


def test_fmt_citation_key():
    assert fmt.get_citation_key({"citationKey": "foo2024"}) == "foo2024"
    assert fmt.get_citation_key({"extra": "Citation Key: bar2025\nother"}) == "bar2025"
    assert fmt.get_citation_key({}) is None

check("formatters.get_citation_key", test_fmt_citation_key)


def test_fmt_sort():
    import io, contextlib
    items = [
        {"data": {"key": "B", "title": "Beta",  "itemType": "book",  "date": "2020", "creators": []}},
        {"data": {"key": "A", "title": "Alpha", "itemType": "article","date": "2023", "creators": []}},
    ]
    # sort by name: Alpha before Beta
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fmt.print_ls([], items, sort_key="name")
    lines = [l for l in buf.getvalue().splitlines() if l.strip()]
    assert lines[0].startswith("Alpha") or "Alpha" in lines[0], f"Expected Alpha first: {lines}"

check("formatters.print_ls sorting by name", test_fmt_sort)

# ---------------------------------------------------------------------------
# 6. cache.py — sync_age_human()
# ---------------------------------------------------------------------------

import cache as _cache


def test_sync_age_unknown():
    orig = _cache.CACHE_FILE
    _cache.CACHE_FILE = "/tmp/__zotcli_no_cache.json"
    try:
        age = _cache.sync_age_human()
        assert age == "unknown"
    finally:
        _cache.CACHE_FILE = orig

check("cache.sync_age_human: unknown when no cache", test_sync_age_unknown)


def test_sync_age_just_now():
    from datetime import datetime, timezone
    orig = _cache.CACHE_FILE
    with tempfile.NamedTemporaryFile(suffix=".json", mode="w", delete=False) as tmp:
        import json as _json
        _json.dump({"collections": [], "updated_at": datetime.now(timezone.utc).isoformat()}, tmp)
        tmp_path = tmp.name
    _cache.CACHE_FILE = tmp_path
    try:
        age = _cache.sync_age_human()
        assert age == "just now", f"got {age!r}"
    finally:
        _cache.CACHE_FILE = orig
        try: os.unlink(tmp_path)
        except OSError: pass

check("cache.sync_age_human: just now", test_sync_age_just_now)

# ---------------------------------------------------------------------------
# 7. finder.py — local filter patterns
# ---------------------------------------------------------------------------

import finder as _finder

find_items = [
    {"data": {"key": "A1", "citationKey": "smith2020",
              "title": "Deep Learning", "itemType": "journalArticle",
              "date": "2020", "creators": [{"lastName": "Smith"}],
              "tags": [{"tag": "ML"}], "collections": ["C1"]}},
    {"data": {"key": "A2", "citationKey": "jones2022",
              "title": "Natural Language Processing", "itemType": "book",
              "date": "2022", "creators": [{"lastName": "Jones"}],
              "tags": [{"tag": "NLP"}], "collections": ["C2"]}},
]


def test_find_title():
    r = _finder.find_in_collection(find_items, "deep")
    assert len(r) == 1
    assert r[0]["data"]["citationKey"] == "smith2020"

check("finder: find by title substring", test_find_title)


def test_find_creator():
    r = _finder.find_in_collection(find_items, "jones", field="creator")
    assert len(r) == 1
    assert r[0]["data"]["citationKey"] == "jones2022"

check("finder: find by creator", test_find_creator)


def test_find_tag():
    r = _finder.find_in_collection(find_items, pattern=None, tag="ML")
    assert len(r) == 1
    assert r[0]["data"]["citationKey"] == "smith2020"

check("finder: filter by tag", test_find_tag)


def test_find_type():
    r = _finder.find_in_collection(find_items, pattern=None, item_type="book")
    assert len(r) == 1
    assert r[0]["data"]["citationKey"] == "jones2022"

check("finder: filter by item type", test_find_type)


def test_find_no_match():
    r = _finder.find_in_collection(find_items, "zzznomatch")
    assert len(r) == 0

check("finder: no match returns empty list", test_find_no_match)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
