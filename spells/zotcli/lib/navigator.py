"""
navigator.py — path resolution and collection tree traversal.
Pure functions, no state or I/O.
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
    """Build the full ~ path string for a collection key."""
    if key is None:
        return "~"
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
    return "~/" + "/".join(parts)


def resolve_path(current_key, current_path, path_string, collections,
                 previous_key=None, previous_path=None):
    """
    Resolve path_string relative to (current_key, current_path).

    Returns (collection_key, path_string) — key is None at root (~).
    Raises ValueError with a descriptive message on failure.

    Supported forms:
      ~             root
      ~/foo/bar     absolute from root
      foo           child named foo in current level
      ../foo        up then down
      ..            parent
      -             previous location
    """
    if path_string == "-":
        if previous_path is None:
            raise ValueError("No previous location")
        return previous_key, previous_path

    if path_string in ("", "~"):
        return None, "~"

    if path_string.startswith("~/"):
        parts = [p for p in path_string[2:].split("/") if p]
        return _traverse(None, "~", parts, collections)

    if path_string.startswith("/"):
        parts = [p for p in path_string[1:].split("/") if p]
        return _traverse(None, "~", parts, collections)

    # Relative path
    parts = [p for p in path_string.split("/") if p]
    return _traverse(current_key, current_path, parts, collections)


def _traverse(start_key, start_path, parts, collections):
    key  = start_key
    path = start_path

    for part in parts:
        if part == ".":
            continue

        if part == "..":
            if key is None:
                raise ValueError("Already at root (~)")
            parent = get_parent_key(collections, key)
            key = parent
            if parent is None:
                path = "~"
            else:
                # Strip last segment
                path = path.rsplit("/", 1)[0] if "/" in path else "~"
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
                f"Collection '{part}' not found in current level.\n"
                f"Available: {avail_str or '(empty)'}"
            )
        data = match.get("data", match)
        key  = data["key"]
        path = f"{path}/{part}" if path != "~" else f"~/{part}"

    return key, path
