#!/usr/bin/env python3
"""
commands.py — zotcli subcommand dispatcher (v3).
Called from bin/zotcli: python3 lib/commands.py <subcommand> [args...]

Env var export protocol:
  Commands that modify state emit __ZOTCLI_ENV__ lines to stdout.
  The shell wrapper parses and exports them.
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
import config     as _config
import finder     as _finder
import formatters as _fmt
import navigator  as _nav
import state      as _state


def _fresh():
    return os.environ.get("ZOTCLI_FRESH", "false") == "true"


def _collections():
    cfg = _config.load_config()
    ttl = _config.get_value(cfg, "cache.ttl_seconds") or 3600
    return _cache.get_collections(fresh=_fresh(), ttl_seconds=ttl)


def _zot():
    from client import get_zotero
    return get_zotero()


def _emit_env(**kwargs):
    """Emit env var export lines for the shell wrapper to pick up."""
    for key, val in kwargs.items():
        print(f"__ZOTCLI_ENV__{key}={val}")


def _emit_state_env(st):
    """Emit ZOTCLI_PATH from current state."""
    path = _state.full_path(st)
    _emit_env(ZOTCLI_PATH=path)


def _emit_sync_age():
    """Emit ZOTCLI_SYNC_AGE after a cache operation."""
    age = _cache.sync_age_human()
    _emit_env(ZOTCLI_SYNC_AGE=age)


def _fetch_items(zot, col_key):
    """Fetch items for a collection. Returns [] at root."""
    if col_key is None:
        return []
    try:
        return zot.everything(zot.collection_items(col_key))
    except Exception:
        return zot.collection_items(col_key)


def _find_item_strict(items, query):
    """
    Find one item by citation key, item key, or exact title only.
    Raises ValueError if not found.
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

    raise ValueError(
        f"'{query}' not found. Use 'zotcli find' to search."
    )


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
    path_arg = args[0] if args else "^"
    st = _state.read_state()
    collections = _collections()

    # Fetch items for item navigation if we're in a collection
    items = None
    if st["collection_key"] is not None and path_arg not in ("^", ""):
        try:
            zot = _zot()
            items = _fetch_items(zot, st["collection_key"])
        except SystemExit:
            pass  # No credentials: collection-only navigation

    try:
        new_col_key, new_col_path, new_item_key, new_item_label = _nav.resolve_path(
            current_key=st["collection_key"],
            current_path=st["collection_path"],
            path_string=path_arg,
            collections=collections,
            items=items,
            item_key=st.get("item_key"),
            previous_key=st.get("previous_collection_key"),
            previous_path=st.get("previous_collection_path"),
            previous_item_key=st.get("previous_item_key"),
        )
    except ValueError as e:
        _fmt.error(str(e))
        sys.exit(1)

    _state.write_state(
        collection_key=new_col_key,
        collection_path=new_col_path,
        item_key=new_item_key,
        item_label=new_item_label,
        previous_collection_key=st["collection_key"],
        previous_collection_path=st["collection_path"],
        previous_item_key=st.get("item_key"),
    )
    new_st = _state.read_state()
    display = _state.full_path(new_st)
    print(display)
    _emit_state_env(new_st)


def cmd_pwd(args):
    st = _state.read_state()
    _fmt.print_pwd(_state.full_path(st))


def cmd_ls(args):
    cfg = _config.load_config()
    sort_key = _config.get_value(cfg, "ls.default_sort") or "name"
    reverse  = _config.get_value(cfg, "ls.sort_reverse") or False
    unfiled  = False

    # Parse flags
    positional = []
    i = 0
    while i < len(args):
        if args[i] == "--sort" and i + 1 < len(args):
            sort_key = args[i + 1]
            i += 2
        elif args[i].startswith("--sort="):
            sort_key = args[i][7:]
            i += 1
        elif args[i] == "--reverse":
            reverse = True
            i += 1
        elif args[i] == "--unfiled":
            unfiled = True
            i += 1
        else:
            positional.append(args[i])
            i += 1

    st = _state.read_state()
    collections = _collections()

    # If inside an item, list its children
    if st.get("item_key") and not positional and not unfiled:
        zot = _zot()
        children = zot.children(st["item_key"])
        _fmt.print_children(children)
        return

    # Unfiled: list items with no collection
    if unfiled:
        if st["collection_key"] is not None:
            _fmt.error("--unfiled is only available at root (^)")
            sys.exit(1)
        zot = _zot()
        all_items = zot.everything(zot.items())
        unfiled_items = [
            it for it in all_items
            if not it.get("data", it).get("collections")
            and it.get("data", it).get("itemType") not in ("attachment", "note")
        ]
        _fmt.print_ls([], unfiled_items, sort_key=sort_key, reverse=reverse)
        return

    if not positional:
        # List current collection
        target_key = st["collection_key"]
        sub_cols   = _nav.get_children(collections, target_key)
        zot        = _zot()
        items      = _fetch_items(zot, target_key)
        _fmt.print_ls(sub_cols, items, sort_key=sort_key, reverse=reverse,
                      current_collection_key=target_key)
        return

    ref = positional[0]

    # Try to resolve as a collection path first
    try:
        target_key, _, _, _ = _nav.resolve_path(
            current_key=st["collection_key"],
            current_path=st["collection_path"],
            path_string=ref,
            collections=collections,
        )
        sub_cols = _nav.get_children(collections, target_key)
        zot      = _zot()
        items    = _fetch_items(zot, target_key)
        _fmt.print_ls(sub_cols, items, sort_key=sort_key, reverse=reverse,
                      current_collection_key=target_key)
    except ValueError:
        # Not a collection — treat as item reference, list children
        zot   = _zot()
        items = _fetch_items(zot, st["collection_key"])
        try:
            item = _find_item_strict(items, ref)
        except ValueError as e:
            _fmt.error(str(e))
            sys.exit(1)
        children = zot.children(item.get("data", item)["key"])
        _fmt.print_children(children)


def cmd_tree(args):
    depth = None
    i = 0
    while i < len(args):
        if args[i] == "--depth" and i + 1 < len(args):
            try:
                depth = int(args[i + 1])
            except ValueError:
                _fmt.error(f"--depth must be an integer, got '{args[i+1]}'")
                sys.exit(1)
            i += 2
        elif args[i].startswith("--depth="):
            try:
                depth = int(args[i][8:])
            except ValueError:
                _fmt.error(f"--depth must be an integer")
                sys.exit(1)
            i += 1
        else:
            i += 1

    st = _state.read_state()
    collections = _collections()
    _fmt.print_tree(collections, parent_key=st["collection_key"], depth=depth)


def cmd_cat(args):
    if not args:
        print("Usage: zotcli cat <item>[:<child>]", file=sys.stderr)
        sys.exit(1)

    st = _state.read_state()
    item_ref, child_ref = _parse_ref(args[0])

    # If inside an item and ref looks like a child, resolve from current item
    if st.get("item_key") and child_ref is None:
        zot = _zot()
        children = zot.children(st["item_key"])
        child = _find_child(children, item_ref)
        if child:
            _fmt.print_item_info(child)
            return
        # Fall through: maybe they meant a different item in the same collection

    zot   = _zot()
    items = _fetch_items(zot, st["collection_key"])

    try:
        item = _find_item_strict(items, item_ref)
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
        print("Usage: zotcli get <item>[:<child>] [--bibtex|--json|--bib] [--style <csl>] [-o <path>]",
              file=sys.stderr)
        sys.exit(1)

    cfg = _config.load_config()
    default_format = _config.get_value(cfg, "get.default_format") or "bibtex"
    bib_style = _config.get_value(cfg, "get.bib_style") or "apa"

    # Parse flags
    ref         = None
    output_path = None
    want_bibtex = False
    want_json   = False
    want_bib    = False
    i = 0
    while i < len(args):
        if args[i] == "--bibtex":
            want_bibtex = True
        elif args[i] == "--json":
            want_json = True
        elif args[i] == "--bib":
            want_bib = True
        elif args[i] == "--style" and i + 1 < len(args):
            bib_style = args[i + 1]
            i += 1
        elif args[i].startswith("--style="):
            bib_style = args[i][8:]
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
        item = _find_item_strict(items, item_ref)
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

    # Determine format
    if not want_bibtex and not want_json and not want_bib:
        if default_format == "json":
            want_json = True
        elif default_format == "bib":
            want_bib = True
        else:
            want_bibtex = True

    # BibTeX export
    if want_bibtex:
        zot.add_parameters(format="bibtex")
        try:
            result = zot.item(item_key)
            if isinstance(result, (str, bytes)):
                print(result if isinstance(result, str) else result.decode())
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

    # Formatted bibliography (bib)
    if want_bib:
        zot.add_parameters(format="bib", style=bib_style)
        try:
            result = zot.item(item_key)
            if isinstance(result, (str, bytes)):
                print(result if isinstance(result, str) else result.decode())
            else:
                print(result)
        finally:
            zot.add_parameters(format="json")
        return


def cmd_find(args):
    if not args:
        print("Usage: zotcli find <pattern> [--field <f>] [--scope library] [--tag <tag>] [--type <type>]",
              file=sys.stderr)
        sys.exit(1)

    cfg = _config.load_config()

    pattern    = None
    field      = None
    scope      = "collection"
    tags       = []
    item_type  = None

    i = 0
    while i < len(args):
        if args[i] == "--field" and i + 1 < len(args):
            field = args[i + 1]
            i += 2
        elif args[i].startswith("--field="):
            field = args[i][8:]
            i += 1
        elif args[i] == "--scope" and i + 1 < len(args):
            scope = args[i + 1]
            i += 2
        elif args[i].startswith("--scope="):
            scope = args[i][8:]
            i += 1
        elif args[i] == "--tag" and i + 1 < len(args):
            tags.append(args[i + 1])
            i += 2
        elif args[i].startswith("--tag="):
            tags.append(args[i][6:])
            i += 1
        elif args[i] == "--type" and i + 1 < len(args):
            item_type = args[i + 1]
            i += 2
        elif args[i].startswith("--type="):
            item_type = args[i][7:]
            i += 1
        elif not args[i].startswith("-"):
            pattern = args[i]
            i += 1
        else:
            i += 1

    st = _state.read_state()

    if scope == "library":
        zot = _zot()
        # For multiple tags, run iteratively (AND logic)
        base_tag = tags[0] if tags else None
        results = _finder.find_in_library(zot, pattern, field=field,
                                          tag=base_tag, item_type=item_type)
        for extra_tag in tags[1:]:
            results = [r for r in results
                       if extra_tag.lower() in [
                           t.get("tag", "").lower()
                           for t in r.get("data", r).get("tags", [])
                       ]]

        # Build collections map for display
        collections = _collections()
        col_map = {}
        for col in collections:
            data = col.get("data", col)
            col_map[data.get("key", "")] = _nav.build_path(collections, data.get("key"))

        _fmt.print_find_results(results, collections_map=col_map)
    else:
        zot   = _zot()
        items = _fetch_items(zot, st["collection_key"])
        for tag in tags:
            items = _finder.find_in_collection(items, pattern=None, tag=tag,
                                               item_type=item_type)
        results = _finder.find_in_collection(items, pattern=pattern, field=field,
                                             item_type=item_type if not tags else None)
        _fmt.print_find_results(results)


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
    _emit_sync_age()


def cmd_off(args):
    """Deactivate visual mode and reset navigation state to root."""
    _state.reset_state()
    # The shell wrapper handles unsetting ZOTCLI_VISUAL, ZOTCLI_PATH, ZOTCLI_SYNC_AGE
    # and removing __zotcli_hook from PROMPT_COMMAND.
    # We just emit the env vars to clear them.
    _emit_env(ZOTCLI_PATH="^")


def cmd_config(args):
    cfg = _config.load_config()

    if not args:
        _config.print_config(cfg)
        return

    if len(args) == 1:
        # Print single value
        val = _config.get_value(cfg, args[0])
        if val is None:
            _fmt.error(f"Config key '{args[0]}' not found")
            sys.exit(1)
        print(val)
        return

    # Set value
    dotpath, value = args[0], args[1]
    _config.set_value(dotpath, value)
    print(f"Set {dotpath} = {value}")


# ---------------------------------------------------------------------------
# Hidden subcommands (used internally by shell / tab completion)
# ---------------------------------------------------------------------------

def cmd__complete(args):
    """
    Fast completion helper — reads collection cache only, never calls the API.
    Output: completion_string TAB type, one per line.

    Usage:
      zotcli _complete                 → collections at current state level
      zotcli _complete Pa              → collections starting with "Pa"
      zotcli _complete ^/Books/        → collections inside ^/Books
      zotcli _complete ^/Bo            → top-level collections starting with "Bo"
    """
    cached = _cache.load_cache()
    if not cached:
        return  # No completions without a warm cache — fail silently

    collections = cached.get("collections", [])
    st          = _state.read_state()
    path_arg    = args[0] if args else ""

    if not path_arg:
        parent_key  = st.get("collection_key")
        prefix      = ""
        path_prefix = ""

    elif path_arg.startswith("^/") or path_arg == "^":
        if path_arg in ("^", "^/"):
            parent_key  = None
            prefix      = ""
            path_prefix = "^/"
        elif path_arg.endswith("/"):
            try:
                col_key, _, _, _ = _nav.resolve_path(
                    None, "^", path_arg.rstrip("/"), collections
                )
                parent_key = col_key
            except ValueError:
                return
            prefix      = ""
            path_prefix = path_arg
        else:
            parent_path, _, partial = path_arg.rpartition("/")
            if parent_path in ("^", ""):
                parent_key = None
            else:
                try:
                    col_key, _, _, _ = _nav.resolve_path(
                        None, "^", parent_path, collections
                    )
                    parent_key = col_key
                except ValueError:
                    return
            prefix      = partial
            path_prefix = parent_path + "/"

    else:
        # Relative path
        parent_key  = st.get("collection_key")
        prefix      = path_arg
        path_prefix = ""

    children = _nav.get_children(collections, parent_key)
    for col in children:
        name = col.get("data", col).get("name", "")
        if not prefix or name.startswith(prefix):
            print(f"{path_prefix}{name}/\tcollection")


def cmd__spell_dir(args):
    """Print SPELL_DIR."""
    print(SPELL_DIR)


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

COMMANDS = {
    "cd":           cmd_cd,
    "pwd":          cmd_pwd,
    "ls":           cmd_ls,
    "tree":         cmd_tree,
    "cat":          cmd_cat,
    "get":          cmd_get,
    "find":         cmd_find,
    "connect":      cmd_connect,
    "sync":         cmd_sync,
    "off":          cmd_off,
    "config":       cmd_config,
    # Hidden
    "_complete":    cmd__complete,
    "_spell_dir":   cmd__spell_dir,
}


def main():
    if len(sys.argv) < 2:
        print("Usage: commands.py <subcommand> [args...]", file=sys.stderr)
        sys.exit(1)

    handler = COMMANDS.get(sys.argv[1])
    if handler is None:
        print(f"Unknown subcommand: {sys.argv[1]!r}. Try 'zotcli --help'.",
              file=sys.stderr)
        sys.exit(1)

    handler(sys.argv[2:])


if __name__ == "__main__":
    main()
