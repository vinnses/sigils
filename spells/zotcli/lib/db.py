"""
db.py — SQLite-backed local database for zotcli.

Replaces the static data/cache.json with a fully-indexed relational store
covering collections, items, tags, attachments, and the mutation queue.

Schema versioning via PRAGMA user_version; migrations run on every open_db().
WAL mode is activated on connection open to allow concurrent readers.
"""
import json
import os
import sqlite3
import tempfile
from datetime import datetime, timezone

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
DB_FILE = os.path.join(SPELL_DIR, "data", "zotcli.db")

# Bump this integer whenever a migration is added below.
_CURRENT_SCHEMA_VERSION = 1


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------

def open_db(path=None):
    """
    Open (or create) the SQLite database, apply WAL mode and FK support,
    run schema migrations, and return the connection.

    Args:
        path: optional override for the DB file path (used in tests).
    """
    db_path = path or DB_FILE
    parent = os.path.dirname(db_path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    conn = sqlite3.connect(db_path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    init_schema(conn)
    return conn


# ---------------------------------------------------------------------------
# Schema / Migrations
# ---------------------------------------------------------------------------

def init_schema(conn):
    """Create tables if absent and run any pending migrations."""
    _create_tables(conn)
    _run_migrations(conn)


def _create_tables(conn):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS collections (
            key        TEXT PRIMARY KEY,
            version    INTEGER NOT NULL DEFAULT 0,
            name       TEXT NOT NULL,
            parent_key TEXT,
            data_json  TEXT NOT NULL DEFAULT '{}'
        );

        CREATE TABLE IF NOT EXISTS items (
            key          TEXT PRIMARY KEY,
            version      INTEGER NOT NULL DEFAULT 0,
            item_type    TEXT NOT NULL DEFAULT '',
            title        TEXT,
            citation_key TEXT,
            data_json    TEXT NOT NULL DEFAULT '{}',
            synced_at    TEXT NOT NULL DEFAULT ''
        );

        CREATE INDEX IF NOT EXISTS idx_items_type  ON items(item_type);
        CREATE INDEX IF NOT EXISTS idx_items_title ON items(title);
        CREATE INDEX IF NOT EXISTS idx_items_ck    ON items(citation_key);

        CREATE TABLE IF NOT EXISTS item_collections (
            item_key       TEXT NOT NULL REFERENCES items(key) ON DELETE CASCADE,
            collection_key TEXT NOT NULL REFERENCES collections(key) ON DELETE CASCADE,
            PRIMARY KEY (item_key, collection_key)
        );

        CREATE INDEX IF NOT EXISTS idx_ic_col ON item_collections(collection_key);

        CREATE TABLE IF NOT EXISTS tags (
            item_key TEXT NOT NULL REFERENCES items(key) ON DELETE CASCADE,
            tag      TEXT NOT NULL,
            tag_type INTEGER DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_tags_tag  ON tags(tag);
        CREATE INDEX IF NOT EXISTS idx_tags_item ON tags(item_key);

        CREATE TABLE IF NOT EXISTS attachments (
            key          TEXT PRIMARY KEY,
            version      INTEGER NOT NULL DEFAULT 0,
            parent_key   TEXT NOT NULL,
            filename     TEXT,
            content_type TEXT,
            data_json    TEXT NOT NULL DEFAULT '{}'
        );

        CREATE INDEX IF NOT EXISTS idx_attach_parent ON attachments(parent_key);

        CREATE TABLE IF NOT EXISTS mutations (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            operation  TEXT NOT NULL,
            payload    TEXT NOT NULL DEFAULT '{}',
            status     TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL DEFAULT '',
            retries    INTEGER DEFAULT 0
        );

        CREATE INDEX IF NOT EXISTS idx_mutations_status ON mutations(status);

        CREATE TABLE IF NOT EXISTS sync_state (
            key   TEXT PRIMARY KEY,
            value TEXT
        );
    """)
    conn.commit()


def _get_user_version(conn):
    return conn.execute("PRAGMA user_version").fetchone()[0]


def _set_user_version(conn, v):
    conn.execute(f"PRAGMA user_version = {v}")
    conn.commit()


def _run_migrations(conn):
    v = _get_user_version(conn)
    if v < 1:
        # v1: baseline — all tables already created above
        _set_user_version(conn, 1)


# ---------------------------------------------------------------------------
# Collections
# ---------------------------------------------------------------------------

def upsert_collections(conn, collections):
    """
    Bulk-replace the collections table from a pyzotero collections list.
    Each element is either a raw pyzotero dict with a top-level 'key' and
    a 'data' sub-dict, or a plain flat dict.
    """
    with conn:
        conn.execute("DELETE FROM collections")
        for col in collections:
            data = col.get("data", col)
            key        = data.get("key") or col.get("key", "")
            version    = col.get("version", data.get("version", 0)) or 0
            name       = data.get("name", "")
            parent_raw = data.get("parentCollection")
            parent_key = parent_raw if parent_raw else None
            conn.execute(
                """INSERT OR REPLACE INTO collections (key, version, name, parent_key, data_json)
                   VALUES (?, ?, ?, ?, ?)""",
                (key, version, name, parent_key, json.dumps(data)),
            )


def get_collections(conn):
    """
    Return the full collection list in the same pyzotero shape:
    [{"key": ..., "version": ..., "data": {...}}, ...]
    """
    rows = conn.execute(
        "SELECT key, version, data_json FROM collections ORDER BY name"
    ).fetchall()
    result = []
    for row in rows:
        data = json.loads(row["data_json"])
        result.append({"key": row["key"], "version": row["version"], "data": data})
    return result


def get_collection_count(conn):
    return conn.execute("SELECT COUNT(*) FROM collections").fetchone()[0]


# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------

def _extract_citation_key(data):
    if "citationKey" in data:
        return data["citationKey"]
    extra = data.get("extra", "")
    if extra:
        for line in extra.splitlines():
            if line.lower().startswith("citation key:"):
                return line.split(":", 1)[1].strip()
    return None


def upsert_items(conn, items):
    """
    Bulk-upsert items. Also rebuilds the tags and item_collections junction rows
    for each item provided.
    """
    now = datetime.now(timezone.utc).isoformat()
    with conn:
        for item in items:
            data      = item.get("data", item)
            key       = data.get("key", "")
            if not key:
                continue
            version   = item.get("version", data.get("version", 0)) or 0
            item_type = data.get("itemType", "")
            title     = data.get("title") or None
            ck        = _extract_citation_key(data)

            conn.execute(
                """INSERT OR REPLACE INTO items
                       (key, version, item_type, title, citation_key, data_json, synced_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (key, version, item_type, title, ck, json.dumps(data), now),
            )

            # Rebuild tags for this item
            conn.execute("DELETE FROM tags WHERE item_key = ?", (key,))
            for tag_obj in data.get("tags", []):
                tag_text = tag_obj.get("tag", "")
                tag_type = tag_obj.get("type", 0)
                if tag_text:
                    conn.execute(
                        "INSERT INTO tags (item_key, tag, tag_type) VALUES (?, ?, ?)",
                        (key, tag_text, tag_type),
                    )

            # Rebuild item_collections for this item
            conn.execute("DELETE FROM item_collections WHERE item_key = ?", (key,))
            for col_key in data.get("collections", []):
                # Only insert if the collection exists (FK constraint)
                exists = conn.execute(
                    "SELECT 1 FROM collections WHERE key = ?", (col_key,)
                ).fetchone()
                if exists:
                    conn.execute(
                        "INSERT OR IGNORE INTO item_collections (item_key, collection_key) VALUES (?, ?)",
                        (key, col_key),
                    )


def upsert_attachments(conn, attachments):
    """Bulk-upsert attachment child items."""
    with conn:
        for att in attachments:
            data         = att.get("data", att)
            key          = data.get("key", "")
            if not key:
                continue
            version      = att.get("version", data.get("version", 0)) or 0
            parent_key   = data.get("parentItem", "")
            filename     = data.get("filename") or data.get("title") or None
            content_type = data.get("contentType") or None
            conn.execute(
                """INSERT OR REPLACE INTO attachments
                       (key, version, parent_key, filename, content_type, data_json)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (key, version, parent_key, filename, content_type, json.dumps(data)),
            )


def get_items_in_collection(conn, col_key):
    """Return items belonging to a collection as pyzotero-shaped dicts."""
    rows = conn.execute(
        """SELECT i.key, i.version, i.data_json
             FROM items i
             JOIN item_collections ic ON ic.item_key = i.key
            WHERE ic.collection_key = ?
            ORDER BY i.title""",
        (col_key,),
    ).fetchall()
    return [{"key": r["key"], "version": r["version"],
             "data": json.loads(r["data_json"])} for r in rows]


def get_unfiled_items(conn):
    """Items with no collection membership (and not attachments/notes)."""
    rows = conn.execute(
        """SELECT i.key, i.version, i.data_json
             FROM items i
            WHERE i.item_type NOT IN ('attachment', 'note')
              AND NOT EXISTS (
                  SELECT 1 FROM item_collections ic WHERE ic.item_key = i.key
              )
            ORDER BY i.title""",
    ).fetchall()
    return [{"key": r["key"], "version": r["version"],
             "data": json.loads(r["data_json"])} for r in rows]


def get_trash_items(conn):
    """Items marked deleted in their data JSON."""
    rows = conn.execute(
        """SELECT key, version, data_json FROM items
            WHERE json_extract(data_json, '$.deleted') = 1
            ORDER BY title"""
    ).fetchall()
    return [{"key": r["key"], "version": r["version"],
             "data": json.loads(r["data_json"])} for r in rows]


def get_duplicate_items(conn):
    """Items sharing (title, item_type) with at least one other item."""
    rows = conn.execute(
        """SELECT i.key, i.version, i.data_json
             FROM items i
            WHERE i.item_type NOT IN ('attachment', 'note')
              AND i.title IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM items i2
                   WHERE i2.key != i.key
                     AND i2.title = i.title
                     AND i2.item_type = i.item_type
              )
            ORDER BY i.title"""
    ).fetchall()
    return [{"key": r["key"], "version": r["version"],
             "data": json.loads(r["data_json"])} for r in rows]


def get_conflict_items(conn):
    """Items that have mutations in 'conflict' status."""
    rows = conn.execute(
        """SELECT DISTINCT i.key, i.version, i.data_json
             FROM items i
             JOIN mutations m ON json_extract(m.payload, '$.item_key') = i.key
            WHERE m.status = 'conflict'
            ORDER BY i.title"""
    ).fetchall()
    return [{"key": r["key"], "version": r["version"],
             "data": json.loads(r["data_json"])} for r in rows]


def get_item_by_key(conn, key):
    """Fetch a single item by its Zotero key. Returns pyzotero-shaped dict or None."""
    row = conn.execute(
        "SELECT key, version, data_json FROM items WHERE key = ?", (key,)
    ).fetchone()
    if row is None:
        return None
    return {"key": row["key"], "version": row["version"],
            "data": json.loads(row["data_json"])}


def delete_item_local(conn, key):
    """Remove an item from the local DB (after a confirmed remote trash/delete)."""
    with conn:
        conn.execute("DELETE FROM items WHERE key = ?", (key,))


def delete_collection_local(conn, key):
    """Remove a collection row from the local DB."""
    with conn:
        conn.execute("DELETE FROM collections WHERE key = ?", (key,))


def update_item_collections_local(conn, item_key, add_col_keys=(), remove_col_keys=()):
    """Modify the item_collections junction for an item without rewriting data_json."""
    with conn:
        for col_key in remove_col_keys:
            conn.execute(
                "DELETE FROM item_collections WHERE item_key = ? AND collection_key = ?",
                (item_key, col_key),
            )
        for col_key in add_col_keys:
            exists = conn.execute(
                "SELECT 1 FROM collections WHERE key = ?", (col_key,)
            ).fetchone()
            if exists:
                conn.execute(
                    "INSERT OR IGNORE INTO item_collections (item_key, collection_key) VALUES (?, ?)",
                    (item_key, col_key),
                )


# ---------------------------------------------------------------------------
# Mutation queue
# ---------------------------------------------------------------------------

def enqueue_mutation(conn, operation, payload):
    """
    Insert a pending mutation and return its row id.

    Args:
        operation: string like 'mkdir', 'rm', 'edit', etc.
        payload:   dict that will be JSON-serialised.
    """
    now = datetime.now(timezone.utc).isoformat()
    with conn:
        cur = conn.execute(
            "INSERT INTO mutations (operation, payload, status, created_at) VALUES (?, ?, 'pending', ?)",
            (operation, json.dumps(payload), now),
        )
    return cur.lastrowid


def get_pending_mutations(conn):
    """Return all mutations with status='pending', ordered by id."""
    rows = conn.execute(
        "SELECT id, operation, payload, status, retries FROM mutations WHERE status = 'pending' ORDER BY id"
    ).fetchall()
    return [
        {
            "id": r["id"],
            "operation": r["operation"],
            "payload": json.loads(r["payload"]),
            "status": r["status"],
            "retries": r["retries"],
        }
        for r in rows
    ]


def mark_mutation(conn, mutation_id, status):
    """Update the status of a mutation row."""
    with conn:
        conn.execute(
            "UPDATE mutations SET status = ? WHERE id = ?",
            (status, mutation_id),
        )


def increment_mutation_retries(conn, mutation_id):
    with conn:
        conn.execute(
            "UPDATE mutations SET retries = retries + 1 WHERE id = ?",
            (mutation_id,),
        )


# ---------------------------------------------------------------------------
# Sync state
# ---------------------------------------------------------------------------

def get_sync_state(conn, key):
    """Return a sync_state value, or None if absent."""
    row = conn.execute(
        "SELECT value FROM sync_state WHERE key = ?", (key,)
    ).fetchone()
    return row["value"] if row else None


def set_sync_state(conn, key, value):
    with conn:
        conn.execute(
            "INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
            (key, str(value) if value is not None else None),
        )


def sync_age_human(conn):
    """
    Return a human-readable string for time since last successful sync.
    Mirrors cache.sync_age_human() so callers can be swapped transparently.
    """
    last = get_sync_state(conn, "last_sync_at")
    if not last:
        return "unknown"
    try:
        updated = datetime.fromisoformat(last)
        age = (datetime.now(timezone.utc) - updated).total_seconds()
    except (ValueError, TypeError):
        return "unknown"

    if age < 60:
        return "just now"
    if age < 3600:
        return f"{int(age // 60)}m ago"
    if age < 86400:
        return f"{int(age // 3600)}h ago"
    return f"{int(age // 86400)}d ago"


def record_sync(conn):
    """Stamp last_sync_at with the current UTC time."""
    set_sync_state(conn, "last_sync_at", datetime.now(timezone.utc).isoformat())
