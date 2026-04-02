#!/usr/bin/env python3
"""
test_db.py — unit tests for lib/db.py (SQLite foundation).
All tests use in-memory or temp-file databases; never touch data/.
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

import db as _db

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
# Helpers
# ---------------------------------------------------------------------------

def _make_conn():
    """Return an in-memory SQLite connection with schema applied."""
    conn = _db.open_db(":memory:")
    return conn


def _sample_collections():
    return [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
        {"key": "COL2", "version": 2,
         "data": {"key": "COL2", "name": "Books",  "parentCollection": False}},
        {"key": "COL3", "version": 3,
         "data": {"key": "COL3", "name": "NLP",    "parentCollection": "COL1"}},
    ]


def _sample_items():
    return [
        {"key": "ITEM1", "version": 10,
         "data": {"key": "ITEM1", "itemType": "journalArticle",
                  "title": "Deep Learning", "citationKey": "lecun2015",
                  "collections": ["COL1"],
                  "tags": [{"tag": "ML"}, {"tag": "DL"}], "date": "2015"}},
        {"key": "ITEM2", "version": 11,
         "data": {"key": "ITEM2", "itemType": "book",
                  "title": "Natural Language Processing", "citationKey": "jurafsky2026",
                  "collections": ["COL1", "COL2"],
                  "tags": [{"tag": "NLP"}], "date": "2026"}},
        {"key": "ITEM3", "version": 12,
         "data": {"key": "ITEM3", "itemType": "journalArticle",
                  "title": "Natural Language Processing",  # duplicate title
                  "citationKey": "manning2019",
                  "collections": [],
                  "tags": [], "date": "2019"}},
    ]


# ---------------------------------------------------------------------------
# 1. open_db / schema
# ---------------------------------------------------------------------------

def test_open_db_memory():
    conn = _make_conn()
    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    ).fetchall()}
    assert "collections" in tables
    assert "items"       in tables
    assert "tags"        in tables
    assert "mutations"   in tables
    assert "sync_state"  in tables
    conn.close()

check("open_db creates all tables", test_open_db_memory)


def test_schema_version():
    conn = _make_conn()
    v = conn.execute("PRAGMA user_version").fetchone()[0]
    assert v == _db._CURRENT_SCHEMA_VERSION, f"expected {_db._CURRENT_SCHEMA_VERSION}, got {v}"
    conn.close()

check("schema version set after init", test_schema_version)


def test_wal_mode():
    conn = _make_conn()
    mode = conn.execute("PRAGMA journal_mode").fetchone()[0]
    # In-memory always returns 'memory'; on-disk should return 'wal'
    assert mode in ("wal", "memory")
    conn.close()

check("WAL mode active", test_wal_mode)


def test_open_db_file():
    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test.db")
        conn = _db.open_db(db_path)
        conn.close()
        assert os.path.isfile(db_path)
        # Second open should not crash
        conn2 = _db.open_db(db_path)
        conn2.close()

check("open_db creates file and is idempotent", test_open_db_file)


# ---------------------------------------------------------------------------
# 2. Collections
# ---------------------------------------------------------------------------

def test_upsert_and_get_collections():
    conn = _make_conn()
    cols = _sample_collections()
    _db.upsert_collections(conn, cols)
    result = _db.get_collections(conn)
    keys = {c["key"] for c in result}
    assert keys == {"COL1", "COL2", "COL3"}
    conn.close()

check("upsert_collections + get_collections round-trip", test_upsert_and_get_collections)


def test_upsert_collections_replaces():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    # Replace with smaller set
    _db.upsert_collections(conn, [
        {"key": "NEWCOL", "version": 99,
         "data": {"key": "NEWCOL", "name": "New", "parentCollection": False}},
    ])
    result = _db.get_collections(conn)
    assert len(result) == 1
    assert result[0]["key"] == "NEWCOL"
    conn.close()

check("upsert_collections replaces on second call", test_upsert_collections_replaces)


def test_get_collections_data_shape():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    result = _db.get_collections(conn)
    for c in result:
        assert "key"     in c
        assert "version" in c
        assert "data"    in c
        assert "name"    in c["data"]
    conn.close()

check("get_collections returns pyzotero-shaped dicts", test_get_collections_data_shape)


def test_parent_key_stored():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    row = conn.execute("SELECT parent_key FROM collections WHERE key='COL3'").fetchone()
    assert row["parent_key"] == "COL1"
    row_root = conn.execute("SELECT parent_key FROM collections WHERE key='COL1'").fetchone()
    assert row_root["parent_key"] is None
    conn.close()

check("parent_key stored correctly (None for root)", test_parent_key_stored)


# ---------------------------------------------------------------------------
# 3. Items
# ---------------------------------------------------------------------------

def test_upsert_items():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    count = conn.execute("SELECT COUNT(*) FROM items").fetchone()[0]
    assert count == 3
    conn.close()

check("upsert_items inserts all items", test_upsert_items)


def test_upsert_items_tags():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    tags = {r[0] for r in conn.execute("SELECT tag FROM tags WHERE item_key='ITEM1'").fetchall()}
    assert tags == {"ML", "DL"}
    conn.close()

check("upsert_items populates tags table", test_upsert_items_tags)


def test_upsert_items_item_collections():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    # ITEM2 belongs to COL1 and COL2
    rows = conn.execute(
        "SELECT collection_key FROM item_collections WHERE item_key='ITEM2' ORDER BY collection_key"
    ).fetchall()
    col_keys = {r[0] for r in rows}
    assert col_keys == {"COL1", "COL2"}
    conn.close()

check("upsert_items populates item_collections", test_upsert_items_item_collections)


def test_get_items_in_collection():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    items = _db.get_items_in_collection(conn, "COL1")
    keys = {i["key"] for i in items}
    assert "ITEM1" in keys
    assert "ITEM2" in keys
    conn.close()

check("get_items_in_collection returns correct items", test_get_items_in_collection)


def test_get_unfiled_items():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    unfiled = _db.get_unfiled_items(conn)
    # ITEM3 has empty collections list
    assert any(i["key"] == "ITEM3" for i in unfiled), f"unfiled keys: {[i['key'] for i in unfiled]}"
    conn.close()

check("get_unfiled_items returns items with no collection", test_get_unfiled_items)


def test_get_duplicate_items():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    # ITEM2 and ITEM3 both have title "Natural Language Processing" and same type? No, different types.
    # Let's add a true duplicate
    _db.upsert_items(conn, [
        {"key": "ITEM4", "version": 1,
         "data": {"key": "ITEM4", "itemType": "journalArticle",
                  "title": "Deep Learning", "collections": [], "tags": []}},
    ])
    dupes = _db.get_duplicate_items(conn)
    dupe_keys = {i["key"] for i in dupes}
    assert "ITEM1" in dupe_keys   # shares "Deep Learning" / journalArticle with ITEM4
    assert "ITEM4" in dupe_keys
    conn.close()

check("get_duplicate_items finds title+type duplicates", test_get_duplicate_items)


def test_get_item_by_key():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    item = _db.get_item_by_key(conn, "ITEM1")
    assert item is not None
    assert item["data"]["citationKey"] == "lecun2015"
    assert _db.get_item_by_key(conn, "NOEXIST") is None
    conn.close()

check("get_item_by_key returns item or None", test_get_item_by_key)


def test_delete_item_local():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    _db.delete_item_local(conn, "ITEM1")
    assert _db.get_item_by_key(conn, "ITEM1") is None
    conn.close()

check("delete_item_local removes item", test_delete_item_local)


def test_update_item_collections_local():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, _sample_items())
    # Add COL3, remove COL1 from ITEM1
    _db.update_item_collections_local(conn, "ITEM1",
                                      add_col_keys=["COL3"],
                                      remove_col_keys=["COL1"])
    rows = conn.execute(
        "SELECT collection_key FROM item_collections WHERE item_key='ITEM1'"
    ).fetchall()
    keys = {r[0] for r in rows}
    assert "COL3" in keys
    assert "COL1" not in keys
    conn.close()

check("update_item_collections_local adds and removes", test_update_item_collections_local)


# ---------------------------------------------------------------------------
# 4. Mutations
# ---------------------------------------------------------------------------

def test_enqueue_mutation():
    conn = _make_conn()
    mid = _db.enqueue_mutation(conn, "mkdir", {"name": "TestCol"})
    assert isinstance(mid, int) and mid > 0
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 1
    assert pending[0]["operation"] == "mkdir"
    assert pending[0]["payload"]["name"] == "TestCol"
    conn.close()

check("enqueue_mutation inserts pending mutation", test_enqueue_mutation)


def test_mark_mutation_done():
    conn = _make_conn()
    mid = _db.enqueue_mutation(conn, "rm", {"item_key": "ITEM1"})
    _db.mark_mutation(conn, mid, "done")
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    conn.close()

check("mark_mutation done removes from pending", test_mark_mutation_done)


def test_mark_mutation_conflict():
    conn = _make_conn()
    mid = _db.enqueue_mutation(conn, "edit", {"item_key": "ITEM1", "changes": {}})
    _db.mark_mutation(conn, mid, "conflict")
    pending = _db.get_pending_mutations(conn)
    assert len(pending) == 0
    row = conn.execute("SELECT status FROM mutations WHERE id=?", (mid,)).fetchone()
    assert row["status"] == "conflict"
    conn.close()

check("mark_mutation conflict persists status", test_mark_mutation_conflict)


def test_increment_retries():
    conn = _make_conn()
    mid = _db.enqueue_mutation(conn, "mkdir", {"name": "X"})
    _db.increment_mutation_retries(conn, mid)
    _db.increment_mutation_retries(conn, mid)
    row = conn.execute("SELECT retries FROM mutations WHERE id=?", (mid,)).fetchone()
    assert row["retries"] == 2
    conn.close()

check("increment_mutation_retries increments correctly", test_increment_retries)


# ---------------------------------------------------------------------------
# 5. Sync state
# ---------------------------------------------------------------------------

def test_sync_state_roundtrip():
    conn = _make_conn()
    _db.set_sync_state(conn, "library_version", "42")
    assert _db.get_sync_state(conn, "library_version") == "42"
    assert _db.get_sync_state(conn, "nonexistent") is None
    conn.close()

check("sync_state get/set round-trip", test_sync_state_roundtrip)


def test_sync_age_human_unknown():
    conn = _make_conn()
    age = _db.sync_age_human(conn)
    assert age == "unknown"
    conn.close()

check("sync_age_human returns 'unknown' when no sync", test_sync_age_human_unknown)


def test_sync_age_human_just_now():
    from datetime import datetime, timezone
    conn = _make_conn()
    _db.set_sync_state(conn, "last_sync_at", datetime.now(timezone.utc).isoformat())
    age = _db.sync_age_human(conn)
    assert age == "just now", f"expected 'just now', got {age!r}"
    conn.close()

check("sync_age_human returns 'just now' after record_sync", test_sync_age_human_just_now)


def test_record_sync():
    conn = _make_conn()
    _db.record_sync(conn)
    age = _db.sync_age_human(conn)
    assert age == "just now"
    conn.close()

check("record_sync stamps last_sync_at", test_record_sync)


# ---------------------------------------------------------------------------
# 6. Trash items
# ---------------------------------------------------------------------------

def test_get_trash_items():
    conn = _make_conn()
    _db.upsert_collections(conn, _sample_collections())
    _db.upsert_items(conn, [
        {"key": "TRASH1", "version": 1,
         "data": {"key": "TRASH1", "itemType": "book",
                  "title": "Deleted Book", "collections": [],
                  "tags": [], "deleted": 1}},
        {"key": "LIVE1", "version": 1,
         "data": {"key": "LIVE1", "itemType": "book",
                  "title": "Live Book", "collections": [],
                  "tags": []}},
    ])
    trash = _db.get_trash_items(conn)
    keys = {i["key"] for i in trash}
    assert "TRASH1" in keys
    assert "LIVE1" not in keys
    conn.close()

check("get_trash_items returns deleted items", test_get_trash_items)


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
import sys as _sys
_sys.exit(1 if failed else 0)
