"""
navigator.py — path resolution and collection tree traversal.
Pure functions, no state or I/O.

Root symbol: ^ (replaces ~)
"""


def get_children(collections, parent_key):
    """Return direct children of parent_key. Use None for top-level."""
    result = []
    for col in collections:
        data = col.get("data", col)
        col_parent = data.get("parentCollection") or None
        if col_parent == parent_key:
            result.append(col)
    return result


def get_parent_key(collections, child_key):
    """Return parent key of child_key, or None if top-level."""
    for col in collections:
        data = col.get("data", col)
        if data.get("key") == child_key:
            parent = data.get("parentCollection")
            return parent if parent else None
    return None


def get_collection_by_key(collections, key):
    """Return collection with the given key, or None."""
    for col in collections:
        data = col.get("data", col)
        if data.get("key") == key:
            return col
    return None


def build_path(collections, key):
    """Build the full ^ path string for a collection key."""
    if key is None:
        return "^"
    parts = []
    cur = key
    while cur:
        col = get_collection_by_key(collections, cur)
        if col is None:
            break
        data = col.get("data", col)
        parts.append(data.get("name", cur))
        cur = data.get("parentCollection") or None
    parts.reverse()
    return "^/" + "/".join(parts)


def resolve_path(current_key, current_path, path_string, collections,
                 items=None, item_key=None,
                 previous_key=None, previous_path=None,
                 previous_item_key=None):
    """
    Resolve path_string relative to (current_key, current_path).

    Returns (collection_key, collection_path, new_item_key, new_item_label).

    Supported forms:
      ^             root
      ^/foo/bar     absolute from root
      foo           child named foo in current level (collection or item)
      ../foo        up then down
      ..            parent (from item: back to collection; from collection: up)
      -             previous location

    When items is provided and a path segment matches an item (by citation key,
    item key, or title) but not a subcollection, the resolution enters the item.
    """
    if path_string == "-":
        if previous_path is None:
            raise ValueError("No previous location")
        return previous_key, previous_path, previous_item_key, None

    if path_string in ("", "^"):
        return None, "^", None, None

    if path_string.startswith("^/"):
        parts = [p for p in path_string[2:].split("/") if p]
        col_key, col_path = _traverse_collections(None, "^", parts, collections)
        return col_key, col_path, None, None

    if path_string.startswith("/"):
        parts = [p for p in path_string[1:].split("/") if p]
        col_key, col_path = _traverse_collections(None, "^", parts, collections)
        return col_key, col_path, None, None

    # Relative path
    parts = [p for p in path_string.split("/") if p]
    return _traverse(current_key, current_path, parts, collections,
                     items=items, current_item_key=item_key)


def _traverse(start_key, start_path, parts, collections,
              items=None, current_item_key=None):
    """
    Traverse a relative path from (start_key, start_path).
    Returns (col_key, col_path, item_key, item_label).
    """
    key       = start_key
    path      = start_path
    item_key  = current_item_key
    item_lbl  = None

    for part in parts:
        if part == ".":
            continue

        if part == "..":
            if item_key is not None:
                # Inside an item: go back to containing collection
                item_key = None
                item_lbl = None
                # path stays as collection path
            elif key is None:
                raise ValueError("Already at root (^)")
            else:
                parent = get_parent_key(collections, key)
                key = parent
                if parent is None:
                    path = "^"
                else:
                    path = path.rsplit("/", 1)[0] if "/" in path else "^"
            continue

        # If we're inside an item, we can't go deeper (children are leaves)
        if item_key is not None:
            raise ValueError(
                f"Cannot navigate into '{part}': already inside an item. "
                "Use 'cd ..' first."
            )

        # Try collection first
        children_cols = get_children(collections, key)
        match_col = next(
            (c for c in children_cols if c.get("data", c).get("name", "") == part),
            None,
        )
        if match_col is not None:
            data = match_col.get("data", match_col)
            key  = data["key"]
            path = f"{path}/{part}" if path != "^" else f"^/{part}"
            continue

        # Try item (if items list provided)
        if items is not None:
            match_item = _find_item_by_ref(items, part)
            if match_item is not None:
                idata    = match_item.get("data", match_item)
                item_key = idata["key"]
                item_lbl = _item_label(idata)
                # Collection key and path stay as-is
                continue

        avail = sorted(c.get("data", c).get("name", "") for c in children_cols)
        avail_str = ", ".join(avail[:8])
        if len(avail) > 8:
            avail_str += f" … ({len(avail)} total)"
        raise ValueError(
            f"Collection '{part}' not found in current level.\n"
            f"Available: {avail_str or '(empty)'}"
        )

    return key, path, item_key, item_lbl


def _traverse_collections(start_key, start_path, parts, collections):
    """Traverse only through collections (for absolute paths). Returns (key, path)."""
    key  = start_key
    path = start_path

    for part in parts:
        if part == ".":
            continue
        if part == "..":
            if key is None:
                raise ValueError("Already at root (^)")
            parent = get_parent_key(collections, key)
            key = parent
            path = path.rsplit("/", 1)[0] if "/" in path else "^"
            if key is None:
                path = "^"
            continue

        children = get_children(collections, key)
        match = next(
            (c for c in children if c.get("data", c).get("name", "") == part),
            None,
        )
        if match is None:
            avail = sorted(c.get("data", c).get("name", "") for c in children)
            avail_str = ", ".join(avail[:8])
            if len(avail) > 8:
                avail_str += f" … ({len(avail)} total)"
            raise ValueError(
                f"Collection '{part}' not found.\n"
                f"Available: {avail_str or '(empty)'}"
            )
        data = match.get("data", match)
        key  = data["key"]
        path = f"{path}/{part}" if path != "^" else f"^/{part}"

    return key, path


def _find_item_by_ref(items, ref):
    """
    Find an item by citation key, item key, or exact title.
    Returns the item dict or None.
    """
    # Citation key
    for item in items:
        data = item.get("data", item)
        ck = _get_citation_key(data)
        if ck and ck == ref:
            return item
    # Item key
    for item in items:
        if item.get("data", item).get("key") == ref:
            return item
    # Exact title
    for item in items:
        if item.get("data", item).get("title", "") == ref:
            return item
    return None


def _get_citation_key(item_data):
    if "citationKey" in item_data:
        return item_data["citationKey"]
    extra = item_data.get("extra", "")
    if extra:
        for line in extra.splitlines():
            if line.lower().startswith("citation key:"):
                return line.split(":", 1)[1].strip()
    return None


def _item_label(item_data):
    ck = _get_citation_key(item_data)
    if ck:
        return ck
    title = item_data.get("title", "")
    if title:
        return title[:14] + "…" if len(title) > 15 else title
    return item_data.get("key", "")
