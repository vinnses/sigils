#!/usr/bin/env python3
"""
test_sync.py — unit tests for lib/sync.py (mutation queue + flush).
Uses a mock pyzotero instance; never makes real HTTP calls.
"""
import json
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

import db   as _db
import sync as _sync

passed = 0
failed = 0


def check(label, fn):
    global passed, failed
    try:
        fn()
        print(f"[pass] {label}")
        passed += 1
    except Exception as e:
        import traceback
        print(f"[fail] {label}: {e}")
        traceback.print_exc()
        failed += 1


# ---------------------------------------------------------------------------
# Mock pyzotero
# ---------------------------------------------------------------------------

class MockZot:
    """Minimal pyzotero mock for testing sync operations."""

    def __init__(self, item_version=5, conflict=False, error=False):
        self._item_version = item_version
        self._conflict     = conflict
        self._error        = error
        self.calls         = []

    def item(self, key):
        self.calls.append(("item", key))
        return {"key": key, "version": self._item_version,
                "data": {"key": key, "itemType": "book",
                         "title": "Mock Title", "collections": ["COL1"],
                         "version": self._item_version}}

    def create_collection(self, data):
        self.calls.append(("create_collection", data))
        if self._error:
            raise RuntimeError("API error")
        name = data[0].get("name", "New")
        return {"successful": {"0": {"key": "NEWCOL", "version": 1,
                                     "data": {"key": "NEWCOL", "name": name,
                                              "parentCollection": None}}},
                "success": {"0": "NEWCOL"}}

    def deletecollection(self, col):
        self.calls.append(("deletecollection", col))
        if self._error:
            raise RuntimeError("API error")

    def update_item(self, patch):
        self.calls.append(("update_item", patch))
        if self._conflict:
            raise _MockPreConditionFailed("412 version mismatch")
        if self._error:
            raise RuntimeError("API error")

    def delete_item(self, item):
        self.calls.append(("delete_item", item))
        if self._error:
            raise RuntimeError("API error")

    def create_items(self, items):
        self.calls.append(("create_items", items))
        return {"successful": {"0": {"key": "NEWNOTE", "version": 1,
                                     "data": items[0]}},
                "success": {"0": "NEWNOTE"}}

    def upload_attachment(self, files, parentid=None):
        self.calls.append(("upload_attachment", files, parentid))

    def item_template(self, item_type):
        return {"title": "", "date": "", "extra": "", "tags": [], "collections": []}


class _MockPreConditionFailed(Exception):
    """Simulates pyzotero.zotero_errors.PreConditionFailed (HTTP 412)."""
    pass


def _make_conn():
    conn = _db.open_db(":memory:")
    _db.upsert_collections(conn, [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
    ])
    _db.upsert_items(conn, [
        {"key": "ITEM1", "version": 5,
         "data": {"key": "ITEM1", "itemType": "book", "title": "Test",
                  "collections": ["COL1"], "tags": []}},
    ])
    return conn


# ---------------------------------------------------------------------------
# _is_version_conflict
# ---------------------------------------------------------------------------

def test_is_version_conflict_true():
    exc = _MockPreConditionFailed("412 precondition failed")
    assert _sync._is_version_conflict(exc)

check("_is_version_conflict detects 412 error", test_is_version_conflict_true)


def test_is_version_conflict_false():
    exc = RuntimeError("network timeout")
    assert not _sync._is_version_conflict(exc)

check("_is_version_conflict ignores network errors", test_is_version_conflict_false)


# ---------------------------------------------------------------------------
# flush_pending — mkdir
# ---------------------------------------------------------------------------

def test_flush_mkdir():
    conn = _make_conn()
    zot  = MockZot()
    _db.enqueue_mutation(conn, "mkdir", {"name": "NewCollection", "parent_key": None})
    _sync.flush_pending(conn, zot)
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0, f"still pending: {pending}"
    assert any(c[0] == "create_collection" for c in zot.calls)
    conn.close()

check("flush_pending mkdir calls create_collection and marks done", test_flush_mkdir)


# ---------------------------------------------------------------------------
# flush_pending — edit success
# ---------------------------------------------------------------------------

def test_flush_edit_success():
    conn = _make_conn()
    zot  = MockZot(item_version=5)
    _db.enqueue_mutation(conn, "edit", {
        "item_key": "ITEM1",
        "changes":  {"title": "Updated Title"},
    })
    _sync.flush_pending(conn, zot)
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    assert any(c[0] == "update_item" for c in zot.calls)
    conn.close()

check("flush_pending edit calls update_item and marks done", test_flush_edit_success)


# ---------------------------------------------------------------------------
# flush_pending — edit version conflict
# ---------------------------------------------------------------------------

def test_flush_edit_conflict():
    conn = _make_conn()
    zot  = MockZot(conflict=True)
    _db.enqueue_mutation(conn, "edit", {
        "item_key": "ITEM1",
        "changes":  {"title": "Conflicting Title"},
    })
    _sync.flush_pending(conn, zot)
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    # Should be marked 'conflict'
    row = conn.execute("SELECT status FROM mutations").fetchone()
    assert row["status"] == "conflict"
    conn.close()

check("flush_pending marks conflict on 412 response", test_flush_edit_conflict)


# ---------------------------------------------------------------------------
# flush_pending — conflict routes to ^/.conflicts
# ---------------------------------------------------------------------------

def test_conflict_routes_to_virtual():
    import vfs as _vfs
    conn = _make_conn()
    zot  = MockZot(conflict=True)
    _db.enqueue_mutation(conn, "edit", {
        "item_key": "ITEM1",
        "changes":  {"title": "Bad"},
    })
    _sync.flush_pending(conn, zot)

    # The item should now appear in ^/.conflicts
    node = _vfs.list_node(conn, None, virtual=".conflicts")
    item_keys = {i["key"] for i in node["items"]}
    assert "ITEM1" in item_keys, f"ITEM1 not in conflicts: {item_keys}"
    conn.close()

check("conflict routes item_key to ^/.conflicts virtual node", test_conflict_routes_to_virtual)


# ---------------------------------------------------------------------------
# flush_pending — error with retry
# ---------------------------------------------------------------------------

def test_flush_error_retry():
    conn = _make_conn()
    zot  = MockZot(error=True)
    _db.enqueue_mutation(conn, "mkdir", {"name": "Fail", "parent_key": None})
    # First flush — retries < max_retries, stays pending
    _sync.flush_pending(conn, zot, max_retries=3)
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 1, "should still be pending after first error"
    row = conn.execute("SELECT retries FROM mutations").fetchone()
    assert row["retries"] == 1
    conn.close()

check("flush_pending error increments retries and stays pending", test_flush_error_retry)


def test_flush_error_exhausted():
    conn = _make_conn()
    zot  = MockZot(error=True)
    _db.enqueue_mutation(conn, "mkdir", {"name": "Fail", "parent_key": None})
    # Flush 3 times to exhaust retries
    for _ in range(3):
        _sync.flush_pending(conn, zot, max_retries=3)
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0, "should no longer be pending after max retries"
    row = conn.execute("SELECT status FROM mutations").fetchone()
    assert row["status"] == "error", f"expected 'error', got {row['status']!r}"
    conn.close()

check("flush_pending marks error after max_retries exhausted", test_flush_error_exhausted)


# ---------------------------------------------------------------------------
# enqueue_and_maybe_flush
# ---------------------------------------------------------------------------

def test_enqueue_and_flush():
    conn = _make_conn()
    zot  = MockZot()
    _sync.enqueue_and_maybe_flush(conn, zot, "mkdir", {"name": "X", "parent_key": None})
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    conn.close()

check("enqueue_and_maybe_flush enqueues and flushes inline", test_enqueue_and_flush)


# ---------------------------------------------------------------------------
# _record_conflict
# ---------------------------------------------------------------------------

def test_record_conflict():
    conn = _make_conn()
    _sync._record_conflict(conn, "ITEM1")
    _sync._record_conflict(conn, "ITEM2")
    _sync._record_conflict(conn, "ITEM1")  # duplicate — should not double-add
    raw = _db.get_sync_state(conn, "conflicts")
    keys = json.loads(raw)
    assert keys.count("ITEM1") == 1
    assert "ITEM2" in keys
    conn.close()

check("_record_conflict stores unique item_keys", test_record_conflict)


# ---------------------------------------------------------------------------
# flush_pending — rm (trash)
# ---------------------------------------------------------------------------

def test_flush_rm_trash():
    conn = _make_conn()
    zot  = MockZot()
    _db.enqueue_mutation(conn, "rm", {
        "item_key":       "ITEM1",
        "collection_key": "COL1",
        "trash":          True,
    })
    _sync.flush_pending(conn, zot)
    assert any(c[0] == "delete_item" for c in zot.calls)
    assert _db.get_item_by_key(conn, "ITEM1") is None
    conn.close()

check("flush_pending rm --trash calls delete_item and removes from DB", test_flush_rm_trash)


# ---------------------------------------------------------------------------
# flush_pending — cp
# ---------------------------------------------------------------------------

def test_flush_cp():
    conn = _make_conn()
    _db.upsert_collections(conn, [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
        {"key": "COL2", "version": 1,
         "data": {"key": "COL2", "name": "Books",  "parentCollection": False}},
    ])
    _db.upsert_items(conn, [
        {"key": "ITEM1", "version": 5,
         "data": {"key": "ITEM1", "itemType": "book", "title": "Test",
                  "collections": ["COL1"], "tags": []}},
    ])
    zot = MockZot()
    _db.enqueue_mutation(conn, "cp", {
        "item_key":            "ITEM1",
        "dest_collection_key": "COL2",
    })
    _sync.flush_pending(conn, zot)
    assert any(c[0] == "update_item" for c in zot.calls)
    conn.close()

check("flush_pending cp calls update_item with new collections", test_flush_cp)


# ---------------------------------------------------------------------------
# flush_pending — touch (create note)
# ---------------------------------------------------------------------------

def test_flush_touch():
    conn = _make_conn()
    zot  = MockZot()
    _db.enqueue_mutation(conn, "touch", {
        "parent_key": "ITEM1",
        "note_title": "my note",
        "note_body":  "some text",
    })
    _sync.flush_pending(conn, zot)
    assert any(c[0] == "create_items" for c in zot.calls)
    conn.close()

check("flush_pending touch calls create_items for note", test_flush_touch)


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
import sys as _sys
_sys.exit(1 if failed else 0)
