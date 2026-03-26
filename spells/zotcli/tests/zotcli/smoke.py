#!/usr/bin/env python3
"""Smoke test — verifies lib modules import and basic API without crashing."""
import os
import sys

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
        failed += 1


# Core modules
check("cache.py imports",     lambda: __import__("cache"))
check("state.py imports",     lambda: __import__("state"))
check("navigator.py imports", lambda: __import__("navigator"))
check("formatters.py imports", lambda: __import__("formatters"))

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

# cache path
import cache
assert "cache.json" in cache.CACHE_FILE
print("[pass] cache.CACHE_FILE resolves correctly")
passed += 1

# state path
import state
assert "state.json" in state.STATE_FILE
print("[pass] state.STATE_FILE resolves correctly")
passed += 1

# state read/write round-trip (uses a temp file to avoid polluting data/)
import tempfile, json as _json
orig_state_file = state.STATE_FILE
with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
    tmp_path = tmp.name
state.STATE_FILE = tmp_path
try:
    state.write_state("KEY1", "~/Foo", "KEY0", "~")
    s = state.read_state()
    assert s["collection_key"] == "KEY1"
    assert s["path"] == "~/Foo"
    assert s["previous_key"] == "KEY0"
    print("[pass] state read/write round-trip")
    passed += 1
except Exception as e:
    print(f"[fail] state round-trip: {e}")
    failed += 1
finally:
    state.STATE_FILE = orig_state_file
    try: os.unlink(tmp_path)
    except OSError: pass

# navigator path resolution
import navigator as nav
cols = [
    {"data": {"key": "ROOT1", "name": "Papers",   "parentCollection": False}},
    {"data": {"key": "ROOT2", "name": "Books",    "parentCollection": False}},
    {"data": {"key": "CHILD1","name": "NLP",      "parentCollection": "ROOT1"}},
]

def test_nav():
    k, p = nav.resolve_path(None, "~", "Papers", cols)
    assert k == "ROOT1" and p == "~/Papers", f"got k={k!r} p={p!r}"
    k, p = nav.resolve_path("ROOT1", "~/Papers", "..", cols)
    assert k is None and p == "~", f"got k={k!r} p={p!r}"
    k, p = nav.resolve_path(None, "~", "~/Papers/NLP", cols)
    assert k == "CHILD1" and p == "~/Papers/NLP", f"got k={k!r} p={p!r}"

check("navigator.resolve_path", test_nav)

# formatters color constants
import formatters as fmt
for attr in ("BOLD", "DIM", "CYAN", "NC"):
    assert hasattr(fmt, attr), f"missing {attr}"
print("[pass] formatters color constants present")
passed += 1

# formatters get_citation_key
def test_ck():
    assert fmt.get_citation_key({"citationKey": "foo2024"}) == "foo2024"
    assert fmt.get_citation_key({"extra": "Citation Key: bar2025\nother"}) == "bar2025"
    assert fmt.get_citation_key({}) is None

check("formatters.get_citation_key", test_ck)

print()
print(f"Results: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
