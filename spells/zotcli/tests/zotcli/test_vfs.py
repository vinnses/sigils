#!/usr/bin/env python3
"""
test_vfs.py — unit tests for lib/vfs.py (Virtual File System layer).
All tests use in-memory SQLite.
"""
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

import db  as _db
import vfs as _vfs

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


def _make_conn():
    conn = _db.open_db(":memory:")
    # Seed collections
    _db.upsert_collections(conn, [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
        {"key": "COL2", "version": 2,
         "data": {"key": "COL2", "name": "Books",  "parentCollection": False}},
        {"key": "COL3", "version": 3,
         "data": {"key": "COL3", "name": "NLP",    "parentCollection": "COL1"}},
    ])
    # Seed items
    _db.upsert_items(conn, [
        {"key": "ITEM1", "version": 10,
         "data": {"key": "ITEM1", "itemType": "journalArticle",
                  "title": "Deep Learning", "citationKey": "lecun2015",
                  "collections": ["COL1"], "tags": [{"tag": "ML"}]}},
        {"key": "ITEM2", "version": 11,
         "data": {"key": "ITEM2", "itemType": "book",
                  "title": "Speech Processing", "citationKey": "jurafsky2026",
                  "collections": [], "tags": []}},
        {"key": "TRASH1", "version": 12,
         "data": {"key": "TRASH1", "itemType": "book",
                  "title": "Old Book", "collections": [],
                  "tags": [], "deleted": 1}},
    ])
    return conn


# ---------------------------------------------------------------------------
# VIRTUAL_NODES constant
# ---------------------------------------------------------------------------

def test_virtual_nodes_set():
    assert ".trash"      in _vfs.VIRTUAL_NODES
    assert ".unfiled"    in _vfs.VIRTUAL_NODES
    assert ".duplicates" in _vfs.VIRTUAL_NODES
    assert ".conflicts"  in _vfs.VIRTUAL_NODES

check("VIRTUAL_NODES contains all four virtual dirs", test_virtual_nodes_set)


def test_is_virtual():
    assert _vfs.is_virtual(".trash")
    assert _vfs.is_virtual(".unfiled")
    assert not _vfs.is_virtual("Papers")
    assert not _vfs.is_virtual("")
    assert not _vfs.is_virtual(".hidden_other")

check("is_virtual correctly identifies virtual nodes", test_is_virtual)


# ---------------------------------------------------------------------------
# virtual_node_entries
# ---------------------------------------------------------------------------

def test_virtual_node_entries_shape():
    entries = _vfs.virtual_node_entries()
    assert len(entries) == 4
    for e in entries:
        assert "key"     in e
        assert "data"    in e
        assert e["data"]["_virtual"] is True
        assert e["data"]["name"].startswith(".")

check("virtual_node_entries returns 4 synthetic collection dicts", test_virtual_node_entries_shape)


# ---------------------------------------------------------------------------
# is_virtual_key
# ---------------------------------------------------------------------------

def test_is_virtual_key():
    assert _vfs.is_virtual_key("__vfs_trash__")     == ".trash"
    assert _vfs.is_virtual_key("__vfs_unfiled__")   == ".unfiled"
    assert _vfs.is_virtual_key("__vfs_conflicts__") == ".conflicts"
    assert _vfs.is_virtual_key("COL1")    is None
    assert _vfs.is_virtual_key(None)      is None
    assert _vfs.is_virtual_key("__vfs_unknown__") is None  # not in VIRTUAL_NODES

check("is_virtual_key decodes synthetic keys", test_is_virtual_key)


# ---------------------------------------------------------------------------
# list_node
# ---------------------------------------------------------------------------

def test_list_node_root():
    conn = _make_conn()
    node = _vfs.list_node(conn, None)
    col_names = {c.get("data", c).get("name") for c in node["collections"]}
    # Real top-level collections
    assert "Papers" in col_names
    assert "Books"  in col_names
    # Virtual nodes
    assert ".trash"   in col_names
    assert ".unfiled" in col_names
    # Subcollection should NOT appear at root
    assert "NLP" not in col_names
    # Root items list should be empty (items live in collections)
    assert node["items"] == []
    conn.close()

check("list_node root returns top-level collections + virtual stubs", test_list_node_root)


def test_list_node_collection():
    conn = _make_conn()
    node = _vfs.list_node(conn, "COL1")
    col_names = {c.get("data", c).get("name") for c in node["collections"]}
    item_keys  = {i["key"] for i in node["items"]}
    assert "NLP"   in col_names   # subcollection
    assert "ITEM1" in item_keys   # item in COL1
    conn.close()

check("list_node collection returns sub-collections + items", test_list_node_collection)


def test_list_node_virtual_trash():
    conn = _make_conn()
    node = _vfs.list_node(conn, None, virtual=".trash")
    assert node["collections"] == []
    item_keys = {i["key"] for i in node["items"]}
    assert "TRASH1" in item_keys
    conn.close()

check("list_node .trash returns deleted items", test_list_node_virtual_trash)


def test_list_node_virtual_unfiled():
    conn = _make_conn()
    node = _vfs.list_node(conn, None, virtual=".unfiled")
    item_keys = {i["key"] for i in node["items"]}
    # ITEM2 has no collections; TRASH1 is deleted (but not in item_collections either)
    assert "ITEM2" in item_keys
    conn.close()

check("list_node .unfiled returns items with no collection", test_list_node_virtual_unfiled)


def test_list_node_virtual_empty():
    conn = _make_conn()
    node = _vfs.list_node(conn, None, virtual=".conflicts")
    assert node["collections"] == []
    assert isinstance(node["items"], list)
    conn.close()

check("list_node .conflicts returns empty list when no conflicts", test_list_node_virtual_empty)


# ---------------------------------------------------------------------------
# resolve_virtual
# ---------------------------------------------------------------------------

def test_resolve_virtual_enter_trash():
    conn = _make_conn()
    result = _vfs.resolve_virtual(conn, [".trash"])
    assert result is not None
    col_key, col_path, item_key, item_label = result
    assert col_key   == "__vfs_trash__"
    assert ".trash"  in col_path
    assert item_key  is None
    conn.close()

check("resolve_virtual ['.trash'] returns virtual key and path", test_resolve_virtual_enter_trash)


def test_resolve_virtual_not_virtual():
    conn = _make_conn()
    result = _vfs.resolve_virtual(conn, ["Papers"])
    assert result is None
    conn.close()

check("resolve_virtual returns None for non-virtual segments", test_resolve_virtual_not_virtual)


def test_resolve_virtual_empty():
    conn = _make_conn()
    assert _vfs.resolve_virtual(conn, []) is None
    conn.close()

check("resolve_virtual returns None for empty segments", test_resolve_virtual_empty)


def test_resolve_virtual_item_in_trash():
    conn = _make_conn()
    result = _vfs.resolve_virtual(conn, [".trash", "TRASH1"])
    assert result is not None
    _, _, item_key, _ = result
    assert item_key == "TRASH1"
    conn.close()

check("resolve_virtual ['.trash', item_key] navigates into item", test_resolve_virtual_item_in_trash)


def test_resolve_virtual_item_not_found():
    conn = _make_conn()
    try:
        _vfs.resolve_virtual(conn, [".trash", "NOEXIST"])
        assert False, "Expected ValueError"
    except ValueError as e:
        assert "not found" in str(e).lower()
    conn.close()

check("resolve_virtual raises ValueError for missing item", test_resolve_virtual_item_not_found)


# ---------------------------------------------------------------------------
# navigator.py integration
# ---------------------------------------------------------------------------

def test_navigator_virtual_path():
    import navigator as nav
    conn = _make_conn()
    # resolve_path with conn should handle .trash
    col_key, col_path, item_key, _ = nav.resolve_path(
        None, nav.ROOT, ".trash", [], conn=conn
    )
    assert col_key  == "__vfs_trash__"
    assert ".trash" in col_path
    assert item_key is None
    conn.close()

check("navigator.resolve_path delegates .trash to vfs", test_navigator_virtual_path)


def test_navigator_no_conn_ignores_virtual():
    import navigator as nav
    # Without conn, virtual paths are NOT resolved — falls through to collection lookup
    cols = [
        {"data": {"key": "C1", "name": ".trash", "parentCollection": False}},
    ]
    # A real collection named ".trash" should still work without conn
    col_key, _, _, _ = nav.resolve_path(None, nav.ROOT, ".trash", cols)
    assert col_key == "C1"

check("navigator.resolve_path without conn uses regular traversal", test_navigator_no_conn_ignores_virtual)


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
import sys as _sys
_sys.exit(1 if failed else 0)
