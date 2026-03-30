"""
sync.py — Mutation queue processor and synchronisation engine.

Responsible for:
  1. Flushing pending mutations to the Zotero Web API via pyzotero.
  2. Version-key conflict detection (HTTP 412) and routing to ^/.conflicts.
  3. Retry logic (up to max_retries, default 3).
  4. Optional background-process spawn so the terminal is not blocked.

Mutation state machine
----------------------
  pending  →  done      (API call succeeded)
           →  conflict  (version mismatch / HTTP 412 — item_key stored in
                          sync_state['conflicts'] as JSON list)
           →  error     (non-412 API error after max_retries exhausted)

The flush loop is intentionally synchronous within a single process; background
execution is achieved by spawning a detached child process that runs
`zotcli _sync_flush` (registered in commands.py).
"""
import json
import os
import sys

import db as _db

_DEFAULT_MAX_RETRIES = 3


# ---------------------------------------------------------------------------
# Flush helpers
# ---------------------------------------------------------------------------

def _dispatch_mutation(conn, zot, mut):
    """
    Execute one mutation against the Zotero API.

    Returns: 'done' | 'conflict' | 'error'
    """
    op      = mut["operation"]
    payload = mut["payload"]

    try:
        if op == "mkdir":
            return _flush_mkdir(conn, zot, payload)
        elif op == "rmdir":
            return _flush_rmdir(conn, zot, payload)
        elif op == "cp":
            return _flush_cp(conn, zot, payload)
        elif op == "mv":
            return _flush_mv(conn, zot, payload)
        elif op == "rm":
            return _flush_rm(conn, zot, payload)
        elif op == "edit":
            return _flush_edit(conn, zot, payload)
        elif op == "touch":
            return _flush_touch(conn, zot, payload)
        elif op == "import_file":
            return _flush_import_file(conn, zot, payload)
        elif op == "set":
            return _flush_set(conn, zot, payload)
        else:
            print(f"sync: unknown operation '{op}' — marking error", file=sys.stderr)
            return "error"
    except Exception as exc:
        msg = str(exc)
        # pyzotero raises zotero_errors.PreConditionFailed for 412
        if _is_version_conflict(exc):
            return "conflict"
        print(f"sync: {op} failed: {msg}", file=sys.stderr)
        return "error"


def _is_version_conflict(exc):
    """Detect a version-key mismatch (HTTP 412) from pyzotero."""
    cls_name = type(exc).__name__
    if "PreConditionFailed" in cls_name or "Conflict" in cls_name:
        return True
    msg = str(exc).lower()
    return "412" in msg or "precondition failed" in msg or "version" in msg and "conflict" in msg


def _record_conflict(conn, item_key):
    """Add item_key to the JSON list stored under sync_state['conflicts']."""
    raw = _db.get_sync_state(conn, "conflicts") or "[]"
    try:
        existing = json.loads(raw)
    except (ValueError, TypeError):
        existing = []
    if item_key and item_key not in existing:
        existing.append(item_key)
    _db.set_sync_state(conn, "conflicts", json.dumps(existing))


# ---------------------------------------------------------------------------
# Individual operation flushers
# ---------------------------------------------------------------------------

def _flush_mkdir(conn, zot, payload):
    name          = payload["name"]
    parent_key    = payload.get("parent_key")
    col_data      = {"name": name}
    if parent_key:
        col_data["parentCollection"] = parent_key
    result = zot.create_collection([col_data])
    # pyzotero returns {"success": {"0": key}, "successful": {...}, ...}
    created = result.get("successful", {})
    if created:
        col_obj = list(created.values())[0]
        _db.upsert_collections(conn, _db.get_collections(conn) + [col_obj])
    return "done"


def _flush_rmdir(conn, zot, payload):
    col_key    = payload["collection_key"]
    trash_items = payload.get("trash_items", False)

    if trash_items:
        items = _db.get_items_in_collection(conn, col_key)
        for item in items:
            try:
                zot.delete_item(item)
                _db.delete_item_local(conn, item.get("data", item)["key"])
            except Exception as e:
                print(f"sync: warning — could not trash item: {e}", file=sys.stderr)

    # Build a minimal collection object for pyzotero.deletecollection
    col_obj = {"key": col_key, "version": 0}
    all_cols = _db.get_collections(conn)
    for c in all_cols:
        if c["key"] == col_key:
            col_obj["version"] = c["version"]
            break
    zot.deletecollection(col_obj)
    _db.delete_collection_local(conn, col_key)
    return "done"


def _flush_cp(conn, zot, payload):
    item_key   = payload["item_key"]
    dest_key   = payload["dest_collection_key"]
    item       = zot.item(item_key)
    data       = item.get("data", item)
    cols       = list(data.get("collections", []))
    if dest_key not in cols:
        cols.append(dest_key)
    patch      = {"key": item_key, "version": item.get("version", data.get("version", 0)), "collections": cols}
    zot.update_item(patch)
    _db.update_item_collections_local(conn, item_key, add_col_keys=[dest_key])
    return "done"


def _flush_mv(conn, zot, payload):
    item_key   = payload["item_key"]
    dest_key   = payload.get("dest_collection_key")
    src_key    = payload.get("src_collection_key")
    new_title  = payload.get("new_title")

    item   = zot.item(item_key)
    data   = item.get("data", item)
    patch  = {"key": item_key, "version": item.get("version", data.get("version", 0))}

    if new_title:
        patch["title"] = new_title
        zot.update_item(patch)
        updated_data = dict(data)
        updated_data["title"] = new_title
        _db.upsert_items(conn, [{"key": item_key, "version": patch["version"], "data": updated_data}])
    else:
        cols = list(data.get("collections", []))
        if src_key and src_key in cols:
            cols.remove(src_key)
        if dest_key and dest_key not in cols:
            cols.append(dest_key)
        patch["collections"] = cols
        zot.update_item(patch)
        add  = [dest_key] if dest_key else []
        rem  = [src_key]  if src_key  else []
        _db.update_item_collections_local(conn, item_key, add_col_keys=add, remove_col_keys=rem)
    return "done"


def _flush_rm(conn, zot, payload):
    item_key   = payload["item_key"]
    col_key    = payload.get("collection_key")
    trash      = payload.get("trash", False)

    if trash:
        item = zot.item(item_key)
        zot.delete_item(item)
        _db.delete_item_local(conn, item_key)
    else:
        item  = zot.item(item_key)
        data  = item.get("data", item)
        cols  = list(data.get("collections", []))
        if col_key and col_key in cols:
            cols.remove(col_key)
        patch = {"key": item_key, "version": item.get("version", data.get("version", 0)), "collections": cols}
        zot.update_item(patch)
        if col_key:
            _db.update_item_collections_local(conn, item_key, remove_col_keys=[col_key])
    return "done"


def _flush_edit(conn, zot, payload):
    item_key = payload["item_key"]
    changes  = payload["changes"]   # dict of field→value

    item    = zot.item(item_key)
    data    = item.get("data", item)
    version = item.get("version", data.get("version", 0))

    patch = {**changes, "key": item_key, "version": version}
    zot.update_item(patch)

    updated = dict(data)
    updated.update(changes)
    _db.upsert_items(conn, [{"key": item_key, "version": version, "data": updated}])
    return "done"


def _flush_touch(conn, zot, payload):
    parent_key  = payload["parent_key"]
    note_title  = payload.get("note_title", "")
    note_body   = payload.get("note_body", "")
    note_item   = {
        "itemType":   "note",
        "parentItem": parent_key,
        "note":       f"<p>{note_body}</p>" if note_body else "",
        "tags":       [],
        "collections": [],
    }
    result = zot.create_items([note_item])
    created = result.get("successful", {})
    if created:
        created_item = list(created.values())[0]
        _db.upsert_attachments(conn, [created_item])
    return "done"


def _flush_import_file(conn, zot, payload):
    parent_key  = payload["parent_key"]
    file_path   = payload["file_path"]
    if not os.path.isfile(file_path):
        print(f"sync: import_file — file not found: {file_path}", file=sys.stderr)
        return "error"
    zot.upload_attachment([file_path], parentid=parent_key)
    return "done"


def _flush_set(conn, zot, payload):
    item_key = payload["item_key"]
    field    = payload["field"]
    value    = payload["value"]
    return _flush_edit(conn, zot, {"item_key": item_key, "changes": {field: value}})


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def flush_pending(conn, zot, max_retries=None):
    """
    Process all pending mutations in insertion order.

    Args:
        conn:        open db connection
        zot:         authenticated pyzotero.Zotero instance
        max_retries: override the default retry cap
    """
    if max_retries is None:
        max_retries = _DEFAULT_MAX_RETRIES

    pending = _db.get_pending_mutations(conn)
    for mut in pending:
        mid    = mut["id"]
        status = _dispatch_mutation(conn, zot, mut)

        if status == "conflict":
            item_key = mut["payload"].get("item_key") or mut["payload"].get("collection_key")
            _record_conflict(conn, item_key)
            _db.mark_mutation(conn, mid, "conflict")
        elif status == "done":
            _db.mark_mutation(conn, mid, "done")
        else:
            # error
            retries = mut["retries"] + 1
            _db.increment_mutation_retries(conn, mid)
            if retries >= max_retries:
                _db.mark_mutation(conn, mid, "error")
            # else: leave as 'pending' for next flush attempt


def enqueue_and_maybe_flush(conn, zot, operation, payload, background=False):
    """
    Enqueue a mutation and immediately attempt to flush it.

    If *background* is True, spawns a detached child process instead of
    blocking the caller.  Falls back to a synchronous flush on spawn failure.

    Args:
        conn:       open db connection
        zot:        pyzotero instance (used for synchronous flush only)
        operation:  mutation type string
        payload:    dict describing the operation
        background: if True, attempt to delegate to a background process
    """
    _db.enqueue_mutation(conn, operation, payload)

    if background:
        try:
            spawn_background_flush()
            return
        except Exception as e:
            print(f"sync: background spawn failed ({e}), flushing inline", file=sys.stderr)

    flush_pending(conn, zot)


def spawn_background_flush():
    """
    Launch a detached child process that runs `zotcli _sync_flush`.

    The child inherits SPELL_DIR and credential env vars; stdout/stderr are
    redirected to /dev/null so they do not pollute the parent's terminal.
    """
    import subprocess
    devnull = open(os.devnull, "w")
    # Locate the zotcli binary relative to SPELL_DIR
    spell_dir  = os.environ.get("SPELL_DIR", "")
    zotcli_bin = os.path.join(spell_dir, "bin", "zotcli") if spell_dir else "zotcli"
    if not os.path.isfile(zotcli_bin):
        zotcli_bin = "zotcli"
    subprocess.Popen(
        [zotcli_bin, "_sync_flush"],
        stdout=devnull,
        stderr=devnull,
        start_new_session=True,
        close_fds=True,
    )
