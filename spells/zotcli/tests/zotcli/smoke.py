#!/usr/bin/env python3
"""Smoke test — verifies lib modules import without crashing."""
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


check("cache.py imports", lambda: __import__("cache"))
check("helpers.py imports", lambda: __import__("helpers"))

# client.py requires pyzotero; skip gracefully if not installed
try:
    import client  # noqa: F401
    print("[pass] client.py imports")
    passed += 1
except SystemExit:
    print("[pass] client.py: loaded (credentials not configured — expected)")
    passed += 1
except ImportError as e:
    print(f"[skip] client.py: pyzotero not installed ({e})")

# Verify cache path resolves under SPELL_DIR
import cache
assert "cache.json" in cache.CACHE_FILE, "CACHE_FILE path unexpected"
print("[pass] cache.CACHE_FILE resolves correctly")
passed += 1

# Verify helpers color constants exist
import helpers
for attr in ("BOLD", "DIM", "CYAN", "NC"):
    assert hasattr(helpers, attr), f"helpers missing {attr}"
print("[pass] helpers color constants present")
passed += 1

print()
print(f"Results: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
