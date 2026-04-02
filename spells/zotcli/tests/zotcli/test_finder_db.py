#!/usr/bin/env python3
"""
test_finder_db.py — unit tests for finder.find_in_db() (SQL-backed search).
All tests use in-memory SQLite; never touches data/.
"""
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

import db     as _db
import finder as _finder

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
    """In-memory DB seeded with collections, items, tags."""
    conn = _db.open_db(":memory:")
    _db.upsert_collections(conn, [
        {"key": "COL1", "version": 1,
         "data": {"key": "COL1", "name": "Papers", "parentCollection": False}},
        {"key": "COL2", "version": 2,
         "data": {"key": "COL2", "name": "Books", "parentCollection": False}},
    ])
    _db.upsert_items(conn, [
        {"key": "ITEM1", "version": 10,
         "data": {"key": "ITEM1", "itemType": "journalArticle",
                  "title": "Deep Learning Fundamentals",
                  "citationKey": "lecun2015",
                  "collections": ["COL1"],
                  "tags": [{"tag": "ML"}, {"tag": "DL"}],
                  "date": "2015",
                  "creators": [{"lastName": "LeCun"}]}},
        {"key": "ITEM2", "version": 11,
         "data": {"key": "ITEM2", "itemType": "book",
                  "title": "Natural Language Processing",
                  "citationKey": "jurafsky2026",
                  "collections": ["COL1", "COL2"],
                  "tags": [{"tag": "NLP"}, {"tag": "ML"}],
                  "date": "2026",
                  "creators": [{"lastName": "Jurafsky"}]}},
        {"key": "ITEM3", "version": 12,
         "data": {"key": "ITEM3", "itemType": "journalArticle",
                  "title": "Reinforcement Learning Survey",
                  "citationKey": "sutton2020",
                  "collections": ["COL2"],
                  "tags": [{"tag": "RL"}],
                  "date": "2020",
                  "creators": [{"lastName": "Sutton"}]}},
        # Attachment — should be excluded from find_in_db results
        {"key": "ATT1", "version": 1,
         "data": {"key": "ATT1", "itemType": "attachment",
                  "title": "Deep Learning PDF",
                  "collections": [], "tags": []}},
        # Note — should also be excluded
        {"key": "NOTE1", "version": 1,
         "data": {"key": "NOTE1", "itemType": "note",
                  "title": "My Notes on Deep Learning",
                  "collections": [], "tags": []}},
    ])
    return conn


# ---------------------------------------------------------------------------
# 1. Search by title
# ---------------------------------------------------------------------------

def test_find_by_title():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "deep learning")
    keys = {r["key"] for r in results}
    assert "ITEM1" in keys, f"ITEM1 not found: {keys}"
    assert "ITEM2" not in keys
    conn.close()

check("find_in_db: search by title substring", test_find_by_title)


def test_find_by_title_case_insensitive():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "NATURAL LANGUAGE")
    keys = {r["key"] for r in results}
    assert "ITEM2" in keys
    conn.close()

check("find_in_db: title search is case-insensitive", test_find_by_title_case_insensitive)


# ---------------------------------------------------------------------------
# 2. Search by citation key
# ---------------------------------------------------------------------------

def test_find_by_citation_key():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "lecun", field="key")
    keys = {r["key"] for r in results}
    assert "ITEM1" in keys
    assert len(results) == 1
    conn.close()

check("find_in_db: search by citation key", test_find_by_citation_key)


# ---------------------------------------------------------------------------
# 3. Search by tag
# ---------------------------------------------------------------------------

def test_find_by_tag():
    conn = _make_conn()
    results = _finder.find_in_db(conn, pattern=None, tags=["RL"])
    keys = {r["key"] for r in results}
    assert keys == {"ITEM3"}, f"expected ITEM3, got {keys}"
    conn.close()

check("find_in_db: filter by single tag", test_find_by_tag)


def test_find_by_multiple_tags():
    conn = _make_conn()
    # AND logic: items must have BOTH ML and DL
    results = _finder.find_in_db(conn, pattern=None, tags=["ML", "DL"])
    keys = {r["key"] for r in results}
    assert keys == {"ITEM1"}, f"expected only ITEM1, got {keys}"
    conn.close()

check("find_in_db: multiple tags use AND logic", test_find_by_multiple_tags)


# ---------------------------------------------------------------------------
# 4. Search by item type
# ---------------------------------------------------------------------------

def test_find_by_item_type():
    conn = _make_conn()
    results = _finder.find_in_db(conn, pattern=None, item_type="book")
    keys = {r["key"] for r in results}
    assert keys == {"ITEM2"}, f"expected ITEM2, got {keys}"
    conn.close()

check("find_in_db: filter by item type", test_find_by_item_type)


# ---------------------------------------------------------------------------
# 5. Search scoped to collection
# ---------------------------------------------------------------------------

def test_find_in_collection_scope():
    conn = _make_conn()
    # Only items in COL2
    results = _finder.find_in_db(conn, pattern=None, collection_key="COL2")
    keys = {r["key"] for r in results}
    assert "ITEM2" in keys
    assert "ITEM3" in keys
    assert "ITEM1" not in keys, f"ITEM1 should not be in COL2: {keys}"
    conn.close()

check("find_in_db: search scoped to collection", test_find_in_collection_scope)


def test_find_title_in_collection():
    conn = _make_conn()
    # "learning" in COL1 — should find ITEM1 only (ITEM3 is in COL2)
    results = _finder.find_in_db(conn, "learning", collection_key="COL1")
    keys = {r["key"] for r in results}
    assert "ITEM1" in keys
    assert "ITEM3" not in keys
    conn.close()

check("find_in_db: title search scoped to collection", test_find_title_in_collection)


# ---------------------------------------------------------------------------
# 6. No match
# ---------------------------------------------------------------------------

def test_find_no_match():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "zzznomatchstring")
    assert len(results) == 0
    conn.close()

check("find_in_db: no match returns empty list", test_find_no_match)


# ---------------------------------------------------------------------------
# 7. No pattern (match all)
# ---------------------------------------------------------------------------

def test_find_no_pattern():
    conn = _make_conn()
    results = _finder.find_in_db(conn, pattern=None)
    keys = {r["key"] for r in results}
    # Should return all 3 real items, excluding attachment and note
    assert keys == {"ITEM1", "ITEM2", "ITEM3"}, f"got {keys}"
    conn.close()

check("find_in_db: no pattern returns all non-attachment/note items", test_find_no_pattern)


# ---------------------------------------------------------------------------
# 8. Excludes attachments and notes
# ---------------------------------------------------------------------------

def test_excludes_attachments_notes():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "deep")
    keys = {r["key"] for r in results}
    assert "ATT1" not in keys, "attachment should be excluded"
    assert "NOTE1" not in keys, "note should be excluded"
    conn.close()

check("find_in_db: excludes attachments and notes", test_excludes_attachments_notes)


# ---------------------------------------------------------------------------
# 9. Search by tag pattern (field="tag")
# ---------------------------------------------------------------------------

def test_find_by_tag_field():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "ml", field="tag")
    keys = {r["key"] for r in results}
    assert "ITEM1" in keys
    assert "ITEM2" in keys
    assert "ITEM3" not in keys
    conn.close()

check("find_in_db: search by tag pattern (field='tag')", test_find_by_tag_field)


# ---------------------------------------------------------------------------
# 10. Search by date/year
# ---------------------------------------------------------------------------

def test_find_by_year():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "2015", field="year")
    keys = {r["key"] for r in results}
    assert "ITEM1" in keys
    assert len(results) == 1
    conn.close()

check("find_in_db: search by year/date", test_find_by_year)


# ---------------------------------------------------------------------------
# 11. Result shape
# ---------------------------------------------------------------------------

def test_result_shape():
    conn = _make_conn()
    results = _finder.find_in_db(conn, "deep learning")
    assert len(results) >= 1
    item = results[0]
    assert "key" in item
    assert "version" in item
    assert "data" in item
    assert isinstance(item["data"], dict)
    assert "title" in item["data"]
    conn.close()

check("find_in_db: results have pyzotero-shaped dicts", test_result_shape)


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print()
print(f"Results: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
