"""
helpers.py — formatting, tree rendering, and item/collection lookups.
Pure functions, no state.
"""
import sys

# ANSI colors: only when stdout is a TTY
if sys.stdout.isatty():
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    CYAN   = "\033[0;36m"
    RED    = "\033[0;31m"
    GREEN  = "\033[0;32m"
    YELLOW = "\033[1;33m"
    NC     = "\033[0m"
else:
    BOLD = DIM = CYAN = RED = GREEN = YELLOW = NC = ""


def _c(code, text):
    """Wrap text in an ANSI code + reset."""
    return f"{code}{text}{NC}" if code else text


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------

def print_collection_tree(collections, parent_key=None, indent=0):
    """Recursive tree renderer. Collection names in bold, keys in dim."""
    for col in collections:
        data = col.get("data", col)
        col_parent = data.get("parentCollection") or False
        expected_parent = parent_key or False
        if col_parent == expected_parent:
            prefix = "  " * indent
            name = _c(BOLD, data.get("name", ""))
            key  = _c(DIM, data.get("key", ""))
            print(f"{prefix}{name}  {key}")
            print_collection_tree(
                collections,
                parent_key=data.get("key"),
                indent=indent + 1,
            )


def print_collection_flat(collections):
    """Flat list: key TAB name TAB parent_name."""
    key_to_name = {
        col.get("data", col).get("key", ""): col.get("data", col).get("name", "")
        for col in collections
    }
    for col in collections:
        data = col.get("data", col)
        key         = data.get("key", "")
        name        = data.get("name", "")
        parent_key  = data.get("parentCollection") or ""
        parent_name = key_to_name.get(parent_key, "") if parent_key else ""
        print(f"{key}\t{name}\t{parent_name}")


def print_items_table(items):
    """Tabular output: key TAB title TAB type TAB date TAB creators."""
    for item in items:
        data = item.get("data", item)
        key      = data.get("key", "")
        title    = _c(CYAN, data.get("title", "(no title)"))
        itype    = _c(DIM, data.get("itemType", ""))
        date     = data.get("date", "")
        creators = data.get("creators", [])
        creator_str = ", ".join(
            c.get("lastName", c.get("name", "")) for c in creators[:3]
        )
        if len(creators) > 3:
            creator_str += " et al."
        print(f"{key}\t{title}\t{itype}\t{date}\t{creator_str}")


def print_item_info(item):
    """Full metadata dump of a single item, key-value formatted."""
    data = item.get("data", item)
    for key, value in sorted(data.items()):
        if isinstance(value, list):
            if not value:
                continue
            print(f"{_c(BOLD, key)}:")
            for entry in value:
                if isinstance(entry, dict):
                    parts = "  " + ", ".join(f"{k}: {v}" for k, v in entry.items())
                    print(parts)
                else:
                    print(f"  {entry}")
        elif value or value == 0:
            print(f"{_c(BOLD, key)}: {value}")


def print_attachments(attachments):
    """List: key TAB filename TAB content_type TAB link_mode."""
    for att in attachments:
        data         = att.get("data", att)
        key          = data.get("key", "")
        filename     = data.get("filename", data.get("title", ""))
        content_type = data.get("contentType", "")
        link_mode    = data.get("linkMode", "")
        print(f"{key}\t{filename}\t{content_type}\t{link_mode}")


# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

def find_collection(zot_or_cache, query):
    """Resolve a collection by exact key or name substring.

    zot_or_cache: pyzotero Zotero instance OR cache dict with 'collections' key.
    Returns collection key string. Exits with error if not found or ambiguous.
    """
    if isinstance(zot_or_cache, dict):
        collections = zot_or_cache.get("collections", [])
    else:
        collections = zot_or_cache.everything(zot_or_cache.collections())

    # Exact key match first
    for col in collections:
        data = col.get("data", col)
        if data.get("key") == query:
            return data["key"]

    # Case-insensitive name substring match
    matches = [
        col for col in collections
        if query.lower() in col.get("data", col).get("name", "").lower()
    ]
    if len(matches) == 1:
        return matches[0].get("data", matches[0])["key"]
    if len(matches) == 0:
        print(f"No collection matching '{query}' found.", file=sys.stderr)
        sys.exit(1)
    names = [m.get("data", m).get("name", "") for m in matches]
    print(f"Ambiguous collection '{query}'. Matches: {', '.join(names)}", file=sys.stderr)
    sys.exit(1)


def find_item(zot_or_cache, query):
    """Resolve an item by exact key or title substring.

    zot_or_cache: pyzotero Zotero instance OR cache dict with 'items' key.
    Returns item key string. Exits with error if not found or ambiguous.
    """
    if isinstance(zot_or_cache, dict):
        items = zot_or_cache.get("items", [])

        # Exact key match first
        for item in items:
            data = item.get("data", item)
            if data.get("key") == query:
                return data["key"]

        # Case-insensitive title substring match
        matches = [
            item for item in items
            if query.lower() in item.get("data", item).get("title", "").lower()
        ]
        if len(matches) == 1:
            return matches[0].get("data", matches[0])["key"]
        if len(matches) == 0:
            print(f"No item matching '{query}' found.", file=sys.stderr)
            sys.exit(1)
        titles = [m.get("data", m).get("title", "") for m in matches[:5]]
        print(f"Ambiguous item '{query}'. Matches: {', '.join(titles)}", file=sys.stderr)
        sys.exit(1)
    else:
        # zot_or_cache is a Zotero instance; use API search
        results = zot_or_cache.items(q=query)

        # Exact key match
        for item in results:
            data = item.get("data", item)
            if data.get("key") == query:
                return data["key"]

        if len(results) == 1:
            return results[0].get("data", results[0])["key"]
        if len(results) == 0:
            print(f"No item matching '{query}' found.", file=sys.stderr)
            sys.exit(1)
        titles = [r.get("data", r).get("title", "") for r in results[:5]]
        print(f"Ambiguous item '{query}'. Matches: {', '.join(titles)}", file=sys.stderr)
        sys.exit(1)
