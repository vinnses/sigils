"""
mutations.py — POSIX-like write operations for zotcli.

Each function validates its inputs locally (including against Zotero item
templates where relevant), applies an optimistic local DB change for instant
terminal feedback, then enqueues a mutation for the sync layer to push to the
Zotero Web API.

All public functions follow the signature:
    op(conn, zot, ...) → None

They raise ValueError on bad input; callers (commands.py) are responsible for
catching and formatting errors.
"""
import json
import os
import subprocess
import sys
import tempfile

import db   as _db
import sync as _sync


# ---------------------------------------------------------------------------
# mkdir — create a collection (or sub-collection)
# ---------------------------------------------------------------------------

def mkdir(conn, zot, name, parent_key=None):
    """
    Create a new Zotero collection.

    Args:
        name:       collection name (must be non-empty)
        parent_key: if set, creates as a sub-collection of that key
    """
    if not name or not name.strip():
        raise ValueError("Collection name must not be empty")
    name = name.strip()

    # Optimistic local insert — use a temporary placeholder key
    placeholder = f"__pending__{name}__"
    _db.upsert_collections(conn, _db.get_collections(conn) + [{
        "key":     placeholder,
        "version": 0,
        "data": {
            "key":              placeholder,
            "name":             name,
            "parentCollection": parent_key or None,
        },
    }])

    _sync.enqueue_and_maybe_flush(conn, zot, "mkdir", {
        "name":       name,
        "parent_key": parent_key,
    })


# ---------------------------------------------------------------------------
# rmdir — delete a collection
# ---------------------------------------------------------------------------

def rmdir(conn, zot, collection_key, trash_items=False):
    """
    Delete a collection.

    Args:
        collection_key: Zotero key of the collection to delete
        trash_items:    if True, also trash all items in the collection
    """
    if not collection_key:
        raise ValueError("Collection key is required")

    # Local optimistic removal
    _db.delete_collection_local(conn, collection_key)

    _sync.enqueue_and_maybe_flush(conn, zot, "rmdir", {
        "collection_key": collection_key,
        "trash_items":    trash_items,
    })


# ---------------------------------------------------------------------------
# cp — add an item to a destination collection (multi-collection support)
# ---------------------------------------------------------------------------

def cp(conn, zot, item_key, dest_collection_key):
    """
    Copy (link) an item into a destination collection.
    Zotero items can belong to multiple collections simultaneously;
    this adds the destination without removing the source.

    Args:
        item_key:            Zotero item key
        dest_collection_key: target collection key
    """
    if not item_key:
        raise ValueError("item_key is required")
    if not dest_collection_key:
        raise ValueError("dest_collection_key is required")

    # Optimistic local update
    _db.update_item_collections_local(conn, item_key, add_col_keys=[dest_collection_key])

    _sync.enqueue_and_maybe_flush(conn, zot, "cp", {
        "item_key":            item_key,
        "dest_collection_key": dest_collection_key,
    })


# ---------------------------------------------------------------------------
# mv — move item between collections, or rename it
# ---------------------------------------------------------------------------

def mv(conn, zot, item_key, dest, src_collection_key=None):
    """
    Move an item or rename it.

    If *dest* contains '/' or looks like a collection key, treats it as a
    collection move (removes src_collection_key, adds dest key).
    If *dest* is a plain string with no path separator, treats it as a rename
    (updates the title field).

    Args:
        item_key:           Zotero item key
        dest:               destination collection key OR new title string
        src_collection_key: collection to remove the item from (move only)
    """
    if not item_key:
        raise ValueError("item_key is required")
    if not dest:
        raise ValueError("dest is required")

    # Decide: rename or move?
    is_move = (
        len(dest) == 8 and dest.isalnum() and dest.upper() == dest
    ) or "/" in dest or _db.get_collections(conn) and any(
        c["key"] == dest for c in _db.get_collections(conn)
    )

    if is_move:
        _db.update_item_collections_local(
            conn, item_key,
            add_col_keys=[dest] if dest else [],
            remove_col_keys=[src_collection_key] if src_collection_key else [],
        )
        _sync.enqueue_and_maybe_flush(conn, zot, "mv", {
            "item_key":            item_key,
            "dest_collection_key": dest,
            "src_collection_key":  src_collection_key,
        })
    else:
        # Rename: update title in local DB
        item = _db.get_item_by_key(conn, item_key)
        if item:
            updated_data = dict(item["data"])
            updated_data["title"] = dest
            _db.upsert_items(conn, [{"key": item_key,
                                     "version": item["version"],
                                     "data": updated_data}])
        _sync.enqueue_and_maybe_flush(conn, zot, "mv", {
            "item_key":  item_key,
            "new_title": dest,
        })


# ---------------------------------------------------------------------------
# rm — unlink item from collection, or trash it
# ---------------------------------------------------------------------------

def rm(conn, zot, item_key, collection_key=None, trash=False):
    """
    Remove an item from a collection or send it to the Zotero trash.

    Without --trash: removes collection_key from the item's collections list.
    With --trash:    marks the item deleted (moves to ^/.trash) and queues API delete.

    Args:
        item_key:       Zotero item key
        collection_key: collection to unlink from (only relevant when trash=False)
        trash:          if True, send to Zotero trash
    """
    if not item_key:
        raise ValueError("item_key is required")

    if trash:
        # Mark deleted in local data_json so ^/.trash picks it up immediately
        item = _db.get_item_by_key(conn, item_key)
        if item:
            updated = dict(item["data"])
            updated["deleted"] = 1
            _db.upsert_items(conn, [{"key": item_key,
                                     "version": item["version"],
                                     "data": updated}])
    else:
        if collection_key:
            _db.update_item_collections_local(conn, item_key, remove_col_keys=[collection_key])

    _sync.enqueue_and_maybe_flush(conn, zot, "rm", {
        "item_key":       item_key,
        "collection_key": collection_key,
        "trash":          trash,
    })


# ---------------------------------------------------------------------------
# edit — open item data in $EDITOR, PATCH only changed fields
# ---------------------------------------------------------------------------

def edit(conn, zot, item_key, use_json=False):
    """
    Dump item data to a temp file, open it in $EDITOR / $VISUAL, compute the
    diff, and PATCH only the changed fields to the API.

    Args:
        item_key: Zotero item key
        use_json: if True, use JSON format; default is YAML
    """
    try:
        import yaml as _yaml
        _HAS_YAML = True
    except ImportError:
        _HAS_YAML = False

    if not item_key:
        raise ValueError("item_key is required")

    # Fetch fresh copy from API (not local cache) to avoid version skew
    item     = zot.item(item_key)
    data     = item.get("data", item)
    original = dict(data)

    suffix = ".json" if use_json or not _HAS_YAML else ".yaml"

    fd, tmppath = tempfile.mkstemp(suffix=suffix, prefix="zotcli_edit_")
    try:
        with os.fdopen(fd, "w") as f:
            if use_json or not _HAS_YAML:
                json.dump(original, f, indent=2, ensure_ascii=False)
            else:
                _yaml.dump(original, f, allow_unicode=True, default_flow_style=False)

        editor = os.environ.get("VISUAL") or os.environ.get("EDITOR") or "vi"
        ret    = subprocess.call([editor, tmppath])
        if ret != 0:
            print(f"edit: editor exited with code {ret}, aborting", file=sys.stderr)
            return

        with open(tmppath) as f:
            if use_json or not _HAS_YAML:
                modified = json.load(f)
            else:
                modified = _yaml.safe_load(f)

        if modified is None:
            print("edit: empty file after edit, aborting", file=sys.stderr)
            return

    finally:
        try:
            os.unlink(tmppath)
        except OSError:
            pass

    # Compute diff — only submit changed keys
    changed = {k: v for k, v in modified.items() if original.get(k) != v}
    # Strip read-only fields that the API rejects
    for ro in ("key", "itemType", "dateAdded", "dateModified"):
        changed.pop(ro, None)

    if not changed:
        print("No changes.")
        return

    print(f"Patching {len(changed)} field(s): {', '.join(changed)}", file=sys.stderr)

    # Enqueue the edit mutation; flush will fetch a fresh version key before PATCH
    _sync.enqueue_and_maybe_flush(conn, zot, "edit", {
        "item_key": item_key,
        "changes":  changed,
    })


# ---------------------------------------------------------------------------
# touch — create a child note on an item
# ---------------------------------------------------------------------------

def touch(conn, zot, parent_key, note_title="", note_body=""):
    """
    Create a new child note item attached to *parent_key*.

    Args:
        parent_key:  Zotero key of the parent item
        note_title:  optional display title (stored in note HTML)
        note_body:   initial note text content
    """
    if not parent_key:
        raise ValueError("parent_key is required")

    _sync.enqueue_and_maybe_flush(conn, zot, "touch", {
        "parent_key": parent_key,
        "note_title": note_title,
        "note_body":  note_body,
    })


# ---------------------------------------------------------------------------
# import_file — upload a local file as a child attachment
# ---------------------------------------------------------------------------

def import_file(conn, zot, file_path, parent_key, attachment_name=None):
    """
    Upload a local file as a child attachment of *parent_key*.

    Args:
        file_path:       absolute or relative path to the local file
        parent_key:      Zotero key of the parent item
        attachment_name: optional display name (defaults to the file basename)
    """
    if not file_path:
        raise ValueError("file_path is required")
    if not parent_key:
        raise ValueError("parent_key is required")

    abs_path = os.path.abspath(file_path)
    if not os.path.isfile(abs_path):
        raise ValueError(f"File not found: {abs_path}")

    name = attachment_name or os.path.basename(abs_path)

    _sync.enqueue_and_maybe_flush(conn, zot, "import_file", {
        "file_path":       abs_path,
        "parent_key":      parent_key,
        "attachment_name": name,
    })


# ---------------------------------------------------------------------------
# set — directly mutate a single field on an item
# ---------------------------------------------------------------------------

def set_field(conn, zot, item_key, field, value):
    """
    Set a single field on an item after validating the field name against the
    Zotero item template for that item type.

    Args:
        item_key: Zotero item key
        field:    field name to update
        value:    new value (string; caller responsible for type conversion)
    """
    if not item_key:
        raise ValueError("item_key is required")
    if not field:
        raise ValueError("field is required")

    # Validate field against item template
    item      = _db.get_item_by_key(conn, item_key)
    if item is None:
        raise ValueError(f"Item '{item_key}' not found in local DB; run 'zotcli sync' first")
    item_type = item["data"].get("itemType", "")
    if item_type and field not in ("title", "date", "extra", "tags", "collections"):
        try:
            template = zot.item_template(item_type)
            if field not in template:
                allowed = ", ".join(sorted(template.keys())[:20])
                raise ValueError(
                    f"Field '{field}' is not valid for item type '{item_type}'.\n"
                    f"Valid fields include: {allowed}…"
                )
        except Exception as e:
            if "not valid" in str(e):
                raise
            # If template fetch fails for any other reason, proceed optimistically

    # Optimistic local update
    updated_data = dict(item["data"])
    updated_data[field] = value
    _db.upsert_items(conn, [{"key": item_key,
                              "version": item["version"],
                              "data": updated_data}])

    _sync.enqueue_and_maybe_flush(conn, zot, "set", {
        "item_key": item_key,
        "field":    field,
        "value":    value,
    })
