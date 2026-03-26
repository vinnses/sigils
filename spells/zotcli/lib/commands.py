#!/usr/bin/env python3
"""
commands.py — zotcli subcommand dispatcher (v2).
Called from bin/zotcli: python3 lib/commands.py <subcommand> [args...]
"""
import json
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

import cache      as _cache
import formatters as _fmt
import navigator  as _nav
import state      as _state


def _fresh():
    return os.environ.get("ZOTCLI_FRESH", "false") == "true"


def _collections():
    return _cache.get_collections(fresh=_fresh())


def _zot():
    from client import get_zotero
    return get_zotero()


def _fetch_items(zot, col_key):
    """Fetch items for a collection. Returns [] at root."""
    if col_key is None:
        return []
    try:
        return zot.everything(zot.collection_items(col_key))
    except Exception:
        return zot.collection_items(col_key)


def _find_item(items, query):
    """
    Find one item by citation key, item key, or title.
    Priority: citation key → item key → exact title → substring title.
    Raises ValueError if not found or ambiguous.
    """
    # Citation key
    for item in items:
        data = item.get("data", item)
        ck = _fmt.get_citation_key(data)
        if ck and ck == query:
            return item

    # Exact item key
    for item in items:
        if item.get("data", item).get("key") == query:
            return item

    # Exact title
    for item in items:
        if item.get("data", item).get("title", "") == query:
            return item

    # Case-insensitive title substring
    matches = [
        item for item in items
        if query.lower() in item.get("data", item).get("title", "").lower()
    ]
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        titles = [m.get("data", m).get("title", "") for m in matches[:5]]
        raise ValueError(f"Ambiguous item '{query}'. Matches: {', '.join(titles)}")
    raise ValueError(f"Item '{query}' not found in current collection")


def _find_child(children, ref):
    """Find an attachment/note by filename, title, or key."""
    for c in children:
        data = c.get("data", c)
        if data.get("key") == ref:
            return c
        fname = data.get("filename") or data.get("title") or ""
        if fname == ref:
            return c
    return None


def _parse_ref(ref):
    """Split 'item' or 'item:child' → (item_ref, child_ref|None)."""
    if ":" in ref:
        a, _, b = ref.partition(":")
        return a.strip(), b.strip()
    return ref, None


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------

def cmd_cd(args):
    path_arg = args[0] if args else "~"
    st = _state.read_state()
    collections = _collections()

    try:
        new_key, new_path = _nav.resolve_path(
            current_key=st["collection_key"],
            current_path=st["path"],
            path_string=path_arg,
            collections=collections,
            previous_key=st.get("previous_key"),
            previous_path=st.get("previous_path"),
        )
    except ValueError as e:
        _fmt.error(str(e))
        sys.exit(1)

    _state.write_state(
        collection_key=new_key,
        path=new_path,
        previous_key=st["collection_key"],
        previous_path=st["path"],
    )
    print(new_path)


def cmd_pwd(args):
    st = _state.read_state()
    _fmt.print_pwd(st["path"])


def cmd_ls(args):
    st = _state.read_state()
    collections = _collections()

    if not args:
        # List current collection
        target_key = st["collection_key"]
        sub_cols   = _nav.get_children(collections, target_key)
        zot        = _zot()
        items      = _fetch_items(zot, target_key)
        _fmt.print_ls(sub_cols, items)
        return

    ref = args[0]

    # Try to resolve as a collection path first
    try:
        target_key, _ = _nav.resolve_path(
            current_key=st["collection_key"],
            current_path=st["path"],
            path_string=ref,
            collections=collections,
        )
        # It's a collection — list it
        sub_cols = _nav.get_children(collections, target_key)
        zot      = _zot()
        items    = _fetch_items(zot, target_key)
        _fmt.print_ls(sub_cols, items)
    except ValueError:
        # Not a collection — treat as item reference, list children
        zot   = _zot()
        items = _fetch_items(zot, st["collection_key"])
        try:
            item = _find_item(items, ref)
        except ValueError as e:
            _fmt.error(str(e))
            sys.exit(1)
        children = zot.children(item.get("data", item)["key"])
        _fmt.print_children(children)


def cmd_tree(args):
    st = _state.read_state()
    collections = _collections()
    _fmt.print_tree(collections, parent_key=st["collection_key"])


def cmd_cat(args):
    if not args:
        print("Usage: zotcli cat <item>[:<child>]", file=sys.stderr)
        sys.exit(1)

    st = _state.read_state()
    item_ref, child_ref = _parse_ref(args[0])

    zot   = _zot()
    items = _fetch_items(zot, st["collection_key"])

    try:
        item = _find_item(items, item_ref)
    except ValueError as e:
        _fmt.error(str(e))
        sys.exit(1)

    if child_ref is None:
        _fmt.print_item_info(item)
        return

    item_key = item.get("data", item)["key"]
    children = zot.children(item_key)
    child    = _find_child(children, child_ref)
    if child is None:
        _fmt.error(f"Child '{child_ref}' not found")
        sys.exit(1)
    _fmt.print_item_info(child)


def cmd_get(args):
    if not args:
        print("Usage: zotcli get <item>[:<child>] [--bibtex|--json] [-o <path>]",
              file=sys.stderr)
        sys.exit(1)

    # Parse flags
    ref         = None
    output_path = None
    want_bibtex = False
    want_json   = False
    i = 0
    while i < len(args):
        if args[i] == "--bibtex":
            want_bibtex = True
        elif args[i] == "--json":
            want_json = True
        elif args[i] == "-o" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 1
        elif ref is None:
            ref = args[i]
        i += 1

    if ref is None:
        _fmt.error("No item reference provided")
        sys.exit(1)

    st = _state.read_state()
    item_ref, child_ref = _parse_ref(ref)

    zot   = _zot()
    items = _fetch_items(zot, st["collection_key"])

    try:
        item = _find_item(items, item_ref)
    except ValueError as e:
        _fmt.error(str(e))
        sys.exit(1)

    item_data = item.get("data", item)
    item_key  = item_data["key"]

    # Download attachment
    if child_ref is not None:
        children = zot.children(item_key)
        child    = _find_child(children, child_ref)
        if child is None:
            _fmt.error(f"Child '{child_ref}' not found")
            sys.exit(1)
        child_data = child.get("data", child)
        child_key  = child_data["key"]
        filename   = child_data.get("filename") or child_data.get("title") or child_key
        dest       = output_path or filename
        print(f"Downloading {filename}…", file=sys.stderr)
        content = zot.file(child_key)
        with open(dest, "wb") as f:
            f.write(content)
        print(f"Saved → {dest}", file=sys.stderr)
        return

    # BibTeX export
    if want_bibtex:
        zot.add_parameters(format="bibtex")
        try:
            result = zot.item(item_key)
            if isinstance(result, str):
                print(result)
            else:
                print(result)
        finally:
            zot.add_parameters(format="json")
        return

    # JSON export
    if want_json:
        result = zot.item(item_key)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    # Default: same as cat
    _fmt.print_item_info(item)


def cmd_connect(args):
    credentials_file = os.path.join(SPELL_DIR, "config", "credentials.env")

    print("zotcli connect — Zotero credential setup")
    print()
    print("You'll need:")
    print("  1. Your Zotero library ID (the numeric user or group ID)")
    print("  2. An API key with at least read access")
    print()
    print("Get them at: https://www.zotero.org/settings/keys")
    print()

    if os.path.exists(credentials_file):
        resp = input("credentials.env already exists. Overwrite? [y/N] ").strip().lower()
        if resp != "y":
            print("Aborted.")
            sys.exit(0)
        print()

    library_id = input("Library ID: ").strip()
    api_key    = input("API key:    ").strip()

    if not library_id or not api_key:
        print("Library ID and API key are both required.", file=sys.stderr)
        sys.exit(1)

    print()
    print("Validating credentials…", end=" ", flush=True)

    try:
        from pyzotero import zotero
    except ImportError:
        print()
        print("pyzotero is not installed. Run: make install", file=sys.stderr)
        sys.exit(1)

    try:
        zot = zotero.Zotero(library_id, "user", api_key)
        zot.collections(limit=1)
        print("OK")
    except Exception as e:
        print("FAILED")
        print(f"Error: {e}", file=sys.stderr)
        print("Check your library ID and API key and try again.", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(credentials_file), exist_ok=True)
    with open(credentials_file, "w") as f:
        f.write(f"ZOTERO_LIBRARY_ID={library_id}\n")
        f.write(f"ZOTERO_API_KEY={api_key}\n")

    print(f"Credentials saved to {credentials_file}")


def cmd_sync(args):
    _cache.invalidate()
    collections = _cache.get_collections(fresh=True)
    print(f"Synced {len(collections)} collections.", file=sys.stderr)


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

COMMANDS = {
    "cd":      cmd_cd,
    "pwd":     cmd_pwd,
    "ls":      cmd_ls,
    "tree":    cmd_tree,
    "cat":     cmd_cat,
    "get":     cmd_get,
    "connect": cmd_connect,
    "sync":    cmd_sync,
}


def main():
    if len(sys.argv) < 2:
        print("Usage: commands.py <subcommand> [args...]", file=sys.stderr)
        sys.exit(1)

    handler = COMMANDS.get(sys.argv[1])
    if handler is None:
        print(f"Unknown subcommand: {sys.argv[1]}", file=sys.stderr)
        sys.exit(1)

    handler(sys.argv[2:])


if __name__ == "__main__":
    main()
