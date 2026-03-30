"""
vfs.py — Virtual File System layer for zotcli.

Maps the Zotero data model onto a directory-like structure that includes
permanent virtual root nodes:

  ^/.trash       → items marked deleted (PRAGMA-backed via data_json)
  ^/.unfiled     → items with no collection membership
  ^/.duplicates  → items sharing title+type with at least one other
  ^/.conflicts   → items with mutations in 'conflict' status

All virtual nodes are dot-prefixed so they sort separately from real collections
and are easy to detect programmatically.
"""
import db as _db

# The canonical set of virtual node names (without the leading dot for lookups).
VIRTUAL_NODES = {".trash", ".unfiled", ".duplicates", ".conflicts"}

# Map virtual node name → db getter function (conn) → [item list]
_VIRTUAL_GETTERS = {
    ".trash":      _db.get_trash_items,
    ".unfiled":    _db.get_unfiled_items,
    ".duplicates": _db.get_duplicate_items,
    ".conflicts":  _db.get_conflict_items,
}


def is_virtual(name):
    """Return True if *name* is a virtual node name (e.g. '.trash')."""
    return name in VIRTUAL_NODES


# ---------------------------------------------------------------------------
# Synthetic collection-like dicts for virtual nodes
# ---------------------------------------------------------------------------

def _virtual_node_entry(name):
    """
    Return a fake collection dict in pyzotero shape so formatters can render it
    alongside real collections without special-casing.
    """
    return {
        "key": f"__vfs_{name[1:]}__",
        "version": 0,
        "data": {
            "key":              f"__vfs_{name[1:]}__",
            "name":             name,
            "parentCollection": None,
            "_virtual":         True,
        },
    }


def virtual_node_entries():
    """Return one synthetic collection dict per virtual node, sorted."""
    return [_virtual_node_entry(n) for n in sorted(VIRTUAL_NODES)]


# ---------------------------------------------------------------------------
# list_node — unified listing for real and virtual locations
# ---------------------------------------------------------------------------

def list_node(conn, collection_key, virtual=None):
    """
    Return {'collections': [...], 'items': [...]} for a given location.

    Args:
        conn:           open sqlite3 connection
        collection_key: Zotero collection key string, or None for root
        virtual:        name of a virtual node (e.g. '.trash'), or None

    Behaviour:
        - virtual is set → return items from that virtual node, no sub-collections
        - collection_key is None, virtual is None → root listing:
              real top-level collections + virtual node stubs
        - collection_key is set → items + sub-collections for that collection
    """
    if virtual is not None:
        getter = _VIRTUAL_GETTERS.get(virtual)
        items = getter(conn) if getter else []
        return {"collections": [], "items": items}

    if collection_key is None:
        # Root: real top-level collections + virtual stubs
        all_cols = _db.get_collections(conn)
        top_level = [
            c for c in all_cols
            if (c.get("data", c).get("parentCollection") or None) is None
        ]
        cols = top_level + virtual_node_entries()
        return {"collections": cols, "items": []}

    # Real collection
    all_cols  = _db.get_collections(conn)
    sub_cols  = [
        c for c in all_cols
        if (c.get("data", c).get("parentCollection") or None) == collection_key
    ]
    items = _db.get_items_in_collection(conn, collection_key)
    return {"collections": sub_cols, "items": items}


# ---------------------------------------------------------------------------
# resolve_virtual — path segment → virtual node info
# ---------------------------------------------------------------------------

def resolve_virtual(conn, path_segments):
    """
    If the first path segment is a virtual node name, resolve the path and return
    a navigator-compatible tuple (col_key, col_path, item_key, item_label).

    Returns None if the path does not start with a virtual node.

    Supported patterns:
        ['.trash']            → enters the virtual node (no item selected)
        ['.trash', item_ref]  → enters item inside virtual node
    """
    if not path_segments:
        return None

    first = path_segments[0]
    if first not in VIRTUAL_NODES:
        return None

    from navigator import ROOT, _path_join, _find_item_by_ref, _item_label

    virtual_path = _path_join(ROOT, first)

    if len(path_segments) == 1:
        # Just entering the virtual dir
        return (f"__vfs_{first[1:]}__", virtual_path, None, None)

    # Navigating into an item inside the virtual node
    item_ref = path_segments[1]
    getter   = _VIRTUAL_GETTERS.get(first)
    items    = getter(conn) if getter else []
    match    = _find_item_by_ref(items, item_ref)
    if match is None:
        available = ", ".join(
            (i.get("data", i).get("citationKey") or i.get("data", i).get("title") or i.get("data", i).get("key", ""))
            for i in items[:8]
        )
        raise ValueError(
            f"Item '{item_ref}' not found in {first}.\n"
            f"Available: {available or '(empty)'}"
        )
    idata    = match.get("data", match)
    item_key = idata["key"]
    label    = _item_label(idata)
    return (f"__vfs_{first[1:]}__", virtual_path, item_key, label)


# ---------------------------------------------------------------------------
# is_virtual_key — test whether a collection_key belongs to a virtual node
# ---------------------------------------------------------------------------

def is_virtual_key(key):
    """Return the virtual node name (e.g. '.trash') for a synthetic key, or None."""
    if key and key.startswith("__vfs_") and key.endswith("__"):
        node_name = "." + key[6:-2]
        return node_name if node_name in VIRTUAL_NODES else None
    return None
