#!/usr/bin/env python3
"""
commands.py — zotcli subcommand dispatcher.
Called from bin/zotcli: python3 lib/commands.py <subcommand> [args...]
"""
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))

import cache as _cache
import helpers as _helpers


def _is_fresh():
    return os.environ.get("ZOTCLI_FRESH", "false") == "true"


def _get_data(fresh=False):
    """Return (collections, items) from cache, refreshing from API if needed."""
    from client import get_zotero

    if not fresh and not _cache.is_stale():
        data = _cache.load_cache()
        if data:
            return data["collections"], data["items"]

    zot = get_zotero()
    print("Fetching from Zotero API...", file=sys.stderr)
    collections = zot.everything(zot.collections())
    items = zot.everything(zot.items())
    _cache.save_cache(collections, items)
    return collections, items


# ---------------------------------------------------------------------------
# Subcommand handlers
# ---------------------------------------------------------------------------

def cmd_collections(args):
    flat = "--flat" in args
    collections, _ = _get_data(fresh=_is_fresh())
    if flat:
        _helpers.print_collection_flat(collections)
    else:
        _helpers.print_collection_tree(collections)


def cmd_items(args):
    if not args:
        print("Usage: zotcli items <collection>", file=sys.stderr)
        sys.exit(1)

    query = args[0]
    collections, all_items = _get_data(fresh=_is_fresh())
    cache_data = {"collections": collections, "items": all_items}

    col_key = _helpers.find_collection(cache_data, query)

    # Filter items belonging to this collection
    col_items = [
        item for item in all_items
        if col_key in item.get("data", item).get("collections", [])
    ]
    _helpers.print_items_table(col_items)


def cmd_info(args):
    if not args:
        print("Usage: zotcli info <item>", file=sys.stderr)
        sys.exit(1)

    query = args[0]
    collections, all_items = _get_data(fresh=_is_fresh())
    cache_data = {"collections": collections, "items": all_items}

    item_key = _helpers.find_item(cache_data, query)

    # Return full item record from cache
    item = next(
        (i for i in all_items if i.get("data", i).get("key") == item_key),
        None,
    )
    if item is None:
        from client import get_zotero
        item = get_zotero().item(item_key)

    _helpers.print_item_info(item)


def cmd_attachments(args):
    if not args:
        print("Usage: zotcli attachments <item>", file=sys.stderr)
        sys.exit(1)

    query = args[0]
    collections, all_items = _get_data(fresh=_is_fresh())
    cache_data = {"collections": collections, "items": all_items}

    item_key = _helpers.find_item(cache_data, query)

    # Children (attachments/notes) are not stored in the top-level items cache;
    # always fetch from API.
    from client import get_zotero
    attachments = get_zotero().children(item_key)
    _helpers.print_attachments(attachments)


def cmd_connect(args):
    """Interactive credential setup."""
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
    print("Validating credentials...", end=" ", flush=True)

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
    """Force-refresh the local cache from the API."""
    from client import get_zotero

    _cache.invalidate()
    zot = get_zotero()
    print("Syncing from Zotero API...", file=sys.stderr)
    collections = zot.everything(zot.collections())
    items = zot.everything(zot.items())
    _cache.save_cache(collections, items)
    print(f"Synced {len(collections)} collections, {len(items)} items.", file=sys.stderr)


# ---------------------------------------------------------------------------
# Dispatch table
# ---------------------------------------------------------------------------

COMMANDS = {
    "collections": cmd_collections,
    "items":       cmd_items,
    "info":        cmd_info,
    "attachments": cmd_attachments,
    "connect":     cmd_connect,
    "sync":        cmd_sync,
}


def main():
    if len(sys.argv) < 2:
        print("Usage: commands.py <subcommand> [args...]", file=sys.stderr)
        sys.exit(1)

    subcommand = sys.argv[1]
    subargs    = sys.argv[2:]

    handler = COMMANDS.get(subcommand)
    if handler is None:
        print(f"Unknown subcommand: {subcommand}", file=sys.stderr)
        sys.exit(1)

    handler(subargs)


if __name__ == "__main__":
    main()
