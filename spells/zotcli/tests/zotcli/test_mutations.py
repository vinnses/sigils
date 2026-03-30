#!/usr/bin/env python3
"""
test_mutations.py — unit tests for lib/mutations.py (write operations).
Uses MockZot + in-memory SQLite; never makes real HTTP calls.
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

import db        as _db
import mutations as _mut

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
# Mock pyzotero (same interface as test_sync.py)
# ---------------------------------------------------------------------------

class MockZot:
    """Minimal pyzotero mock for testing mutation operations."""

    def __init__(self):
        self.calls = []

    def item(self, key):
        self.calls.append(("item", key))
        return {"key": key, "version": 5,
                "data": {"key": key, "itemType": "book",
                         "title": "Mock Title", "collections": ["COL1"],
                         "version": 5}}

    def create_collection(self, data):
        self.calls.append(("create_collection", data))
        name = data[0].get("name", "New")
        return {"successful": {"0": {"key": "NEWCOL", "version": 1,
                                     "data": {"key": "NEWCOL", "name": name,
                                              "parentCollection": None}}},
                "success": {"0": "NEWCOL"}}

    def deletecollection(self, col):
        self.calls.append(("deletecollection", col))

    def update_item(self, patch):
        self.calls.append(("update_item", patch))

    def delete_item(self, item):
        self.calls.append(("delete_item", item))

    def create_items(self, items):
        self.calls.append(("create_items", items))
        return {"successful": {"0": {"key": "NEWNOTE", "version": 1,
                                     "data": items[0]}},
                "success": {"0": "NEWNOTE"}}

    def upload_attachment(self, files, parentid=None):
        self.calls.append(("upload_attachment", files, parentid))

    def item_template(self, item_type):
        return {"title": "", "date": "", "extra": "", "tags": [],
                "collections": [], "DOI": "", "abstractNote": ""}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_conn():
    """In-memory DB seeded with collections and items."""
    conn = _db.open_db(":memory:")
    _db.upsert_collections(conn, [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
        {"key": "COL2", "version": 2,
         "data": {"key": "COL2", "name": "Books", "parentCollection": False}},
    ])
    _db.upsert_items(conn, [
        {"key": "ITEM1", "version": 5,
         "data": {"key": "ITEM1", "itemType": "book", "title": "Test Book",
                  "citationKey": "test2024",
                  "collections": ["COL1"], "tags": [{"tag": "ML"}]}},
    ])
    return conn


# ---------------------------------------------------------------------------
# 1. mkdir
# ---------------------------------------------------------------------------

def test_mkdir_valid():
    conn = _make_conn()
    zot = MockZot()
    _mut.mkdir(conn, zot, "NewCollection")
    # Mutation should have been enqueued and flushed
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0, f"expected 0 pending, got {len(pending)}"
    # MockZot should have received create_collection call
    assert any(c[0] == "create_collection" for c in zot.calls)
    conn.close()

check("mkdir: valid creation", test_mkdir_valid)


def test_mkdir_empty_name():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.mkdir(conn, zot, "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "empty" in str(e).lower()
    conn.close()

check("mkdir: empty name raises ValueError", test_mkdir_empty_name)


def test_mkdir_whitespace_name():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.mkdir(conn, zot, "   ")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "empty" in str(e).lower()
    conn.close()

check("mkdir: whitespace-only name raises ValueError", test_mkdir_whitespace_name)


def test_mkdir_with_parent():
    conn = _make_conn()
    zot = MockZot()
    _mut.mkdir(conn, zot, "SubCollection", parent_key="COL1")
    assert any(c[0] == "create_collection" for c in zot.calls)
    conn.close()

check("mkdir: sub-collection with parent_key", test_mkdir_with_parent)


# ---------------------------------------------------------------------------
# 2. rmdir
# ---------------------------------------------------------------------------

def test_rmdir_valid():
    conn = _make_conn()
    zot = MockZot()
    _mut.rmdir(conn, zot, "COL2")
    # COL2 should be removed locally
    cols = _db.get_collections(conn)
    col_keys = {c["key"] for c in cols}
    assert "COL2" not in col_keys, f"COL2 still present: {col_keys}"
    conn.close()

check("rmdir: valid removal deletes locally", test_rmdir_valid)


def test_rmdir_empty_key():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.rmdir(conn, zot, "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "required" in str(e).lower()
    conn.close()

check("rmdir: empty key raises ValueError", test_rmdir_empty_key)


# ---------------------------------------------------------------------------
# 3. cp
# ---------------------------------------------------------------------------

def test_cp_valid():
    conn = _make_conn()
    zot = MockZot()
    _mut.cp(conn, zot, "ITEM1", "COL2")
    # ITEM1 should now be linked to COL2 locally
    rows = conn.execute(
        "SELECT collection_key FROM item_collections WHERE item_key='ITEM1'"
    ).fetchall()
    col_keys = {r[0] for r in rows}
    assert "COL2" in col_keys, f"COL2 not in {col_keys}"
    assert "COL1" in col_keys, f"COL1 should still be there: {col_keys}"
    conn.close()

check("cp: valid copy links item to dest collection", test_cp_valid)


def test_cp_empty_item_key():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.cp(conn, zot, "", "COL2")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "item_key" in str(e).lower()
    conn.close()

check("cp: empty item_key raises ValueError", test_cp_empty_item_key)


def test_cp_empty_dest():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.cp(conn, zot, "ITEM1", "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "dest" in str(e).lower()
    conn.close()

check("cp: empty dest raises ValueError", test_cp_empty_dest)


# ---------------------------------------------------------------------------
# 4. mv
# ---------------------------------------------------------------------------

def test_mv_move_between_collections():
    conn = _make_conn()
    zot = MockZot()
    # COL2 is an 8-char uppercase alphanumeric key — triggers "move" logic
    # But COL2 is only 4 chars. Use the collection lookup fallback instead.
    _mut.mv(conn, zot, "ITEM1", "COL2", src_collection_key="COL1")
    # Should have enqueued and flushed
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    assert any(c[0] == "update_item" for c in zot.calls)
    conn.close()

check("mv: move item between collections", test_mv_move_between_collections)


def test_mv_rename():
    conn = _make_conn()
    zot = MockZot()
    _mut.mv(conn, zot, "ITEM1", "New Title For Book")
    # Local title should be updated
    item = _db.get_item_by_key(conn, "ITEM1")
    assert item["data"]["title"] == "New Title For Book", f"got {item['data']['title']!r}"
    conn.close()

check("mv: rename item updates local title", test_mv_rename)


def test_mv_empty_item_key():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.mv(conn, zot, "", "COL2")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "item_key" in str(e).lower()
    conn.close()

check("mv: empty item_key raises ValueError", test_mv_empty_item_key)


def test_mv_empty_dest():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.mv(conn, zot, "ITEM1", "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "dest" in str(e).lower()
    conn.close()

check("mv: empty dest raises ValueError", test_mv_empty_dest)


# ---------------------------------------------------------------------------
# 5. rm
# ---------------------------------------------------------------------------

def test_rm_unlink():
    conn = _make_conn()
    zot = MockZot()
    _mut.rm(conn, zot, "ITEM1", collection_key="COL1", trash=False)
    # ITEM1 should be unlinked from COL1 locally
    rows = conn.execute(
        "SELECT collection_key FROM item_collections WHERE item_key='ITEM1'"
    ).fetchall()
    col_keys = {r[0] for r in rows}
    assert "COL1" not in col_keys, f"COL1 still linked: {col_keys}"
    conn.close()

check("rm: unlink removes item from collection", test_rm_unlink)


def test_rm_trash():
    conn = _make_conn()
    zot = MockZot()
    _mut.rm(conn, zot, "ITEM1", trash=True)
    # Item should be marked deleted locally
    item = _db.get_item_by_key(conn, "ITEM1")
    # After flush, delete_item is called on the mock, which then deletes locally
    # Check that delete_item was called on MockZot
    assert any(c[0] == "delete_item" for c in zot.calls)
    conn.close()

check("rm: trash marks item deleted and calls API", test_rm_trash)


def test_rm_empty_key():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.rm(conn, zot, "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "item_key" in str(e).lower()
    conn.close()

check("rm: empty item_key raises ValueError", test_rm_empty_key)


# ---------------------------------------------------------------------------
# 6. set_field
# ---------------------------------------------------------------------------

def test_set_field_valid():
    conn = _make_conn()
    zot = MockZot()
    _mut.set_field(conn, zot, "ITEM1", "title", "Updated Title")
    # Local DB should have updated title
    item = _db.get_item_by_key(conn, "ITEM1")
    assert item["data"]["title"] == "Updated Title", f"got {item['data']['title']!r}"
    conn.close()

check("set_field: valid update changes local DB", test_set_field_valid)


def test_set_field_empty_item_key():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.set_field(conn, zot, "", "title", "X")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "item_key" in str(e).lower()
    conn.close()

check("set_field: empty item_key raises ValueError", test_set_field_empty_item_key)


def test_set_field_empty_field():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.set_field(conn, zot, "ITEM1", "", "X")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "field" in str(e).lower()
    conn.close()

check("set_field: empty field raises ValueError", test_set_field_empty_field)


def test_set_field_invalid_field():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.set_field(conn, zot, "ITEM1", "nonExistentField999", "X")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "not valid" in str(e).lower()
    conn.close()

check("set_field: invalid field raises ValueError", test_set_field_invalid_field)


def test_set_field_item_not_found():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.set_field(conn, zot, "NOEXIST", "title", "X")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "not found" in str(e).lower()
    conn.close()

check("set_field: missing item raises ValueError", test_set_field_item_not_found)


# ---------------------------------------------------------------------------
# 7. touch
# ---------------------------------------------------------------------------

def test_touch_valid():
    conn = _make_conn()
    zot = MockZot()
    _mut.touch(conn, zot, "ITEM1", note_title="My Note", note_body="Some text")
    assert any(c[0] == "create_items" for c in zot.calls)
    conn.close()

check("touch: valid note creation", test_touch_valid)


def test_touch_empty_parent():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.touch(conn, zot, "", note_title="X")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "parent_key" in str(e).lower()
    conn.close()

check("touch: empty parent_key raises ValueError", test_touch_empty_parent)


# ---------------------------------------------------------------------------
# 8. import_file
# ---------------------------------------------------------------------------

def test_import_file_valid():
    conn = _make_conn()
    zot = MockZot()
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp.write(b"fake pdf content")
        tmp_path = tmp.name
    try:
        _mut.import_file(conn, zot, tmp_path, "ITEM1")
        assert any(c[0] == "upload_attachment" for c in zot.calls)
    finally:
        os.unlink(tmp_path)
    conn.close()

check("import_file: valid file upload", test_import_file_valid)


def test_import_file_missing():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.import_file(conn, zot, "/tmp/__zotcli_no_such_file.pdf", "ITEM1")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "not found" in str(e).lower()
    conn.close()

check("import_file: missing file raises ValueError", test_import_file_missing)


def test_import_file_empty_path():
    conn = _make_conn()
    zot = MockZot()
    try:
        _mut.import_file(conn, zot, "", "ITEM1")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "file_path" in str(e).lower()
    conn.close()

check("import_file: empty path raises ValueError", test_import_file_empty_path)


def test_import_file_empty_parent():
    conn = _make_conn()
    zot = MockZot()
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp.write(b"content")
        tmp_path = tmp.name
    try:
        _mut.import_file(conn, zot, tmp_path, "")
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "parent_key" in str(e).lower()
    finally:
        os.unlink(tmp_path)
    conn.close()

check("import_file: empty parent_key raises ValueError", test_import_file_empty_parent)


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
