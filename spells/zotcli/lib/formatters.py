"""
formatters.py — ANSI-aware output formatters for zotcli.

Color detection: sys.stdout.isatty() OR ZOTCLI_COLOR=1 env var.
The shell wrapper sets ZOTCLI_COLOR=1 so colors survive stdout capture.
"""
import os
import sys
import textwrap

# Color detection: TTY or forced via env var (set by shell wrapper)
_color_enabled = sys.stdout.isatty() or os.environ.get("ZOTCLI_COLOR") == "1"

if _color_enabled:
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
    """Wrap text in ANSI code + reset."""
    return f"{code}{text}{NC}" if code else text


# ---------------------------------------------------------------------------
# Citation key extraction
# ---------------------------------------------------------------------------

def get_citation_key(item_data):
    """Extract citation key from item data dict. Returns None if absent."""
    if "citationKey" in item_data:
        return item_data["citationKey"]
    extra = item_data.get("extra", "")
    if extra:
        for line in extra.splitlines():
            if line.lower().startswith("citation key:"):
                return line.split(":", 1)[1].strip()
    return None


def _item_label(item_data):
    """Return citation key, or truncated title, or item key."""
    ck = get_citation_key(item_data)
    if ck:
        return ck
    title = item_data.get("title", "")
    if title:
        return title[:14] + "…" if len(title) > 15 else title
    return item_data.get("key", "")


def _fmt_creators(creators, max_n=3):
    """Format a creator list to a short string."""
    if not creators:
        return ""
    parts = []
    for c in creators[:max_n]:
        name = c.get("lastName") or c.get("name") or ""
        if name:
            parts.append(name)
    result = ", ".join(parts)
    if len(creators) > max_n:
        result += " et al."
    return result


def _sort_key_for_item(item, sort_by):
    """Return a sort key for an item based on sort_by field name."""
    data = item.get("data", item)
    if sort_by == "date":
        return data.get("date", "") or ""
    if sort_by == "type":
        return data.get("itemType", "") or ""
    if sort_by == "creator":
        creators = data.get("creators", [])
        if creators:
            return (creators[0].get("lastName") or creators[0].get("name") or "").lower()
        return ""
    return _item_label(data).lower()


def _is_leaf_item(item_data):
    """Return True if itemType is attachment or note (not a bibliographic item)."""
    return item_data.get("itemType") in ("attachment", "note")


# ---------------------------------------------------------------------------
# Output functions
# ---------------------------------------------------------------------------

def print_pwd(path):
    print(path)


def print_ls(collections, items, sort_key="name", reverse=False,
             current_collection_key=None):
    """
    Mixed listing: collections (bold + /) then items.

    Attachments and notes are excluded — they only appear when inside an item.
    Items in multiple collections with current NOT first get a → prefix.
    """
    for col in sorted(collections,
                      key=lambda c: c.get("data", c).get("name", "").lower()):
        data = col.get("data", col)
        print(_c(BOLD, data.get("name", "") + "/"))

    # Exclude attachments and notes from collection-level view
    bib_items = [it for it in items if not _is_leaf_item(it.get("data", it))]

    if sort_key == "date":
        sorted_items = sorted(bib_items,
                              key=lambda it: _sort_key_for_item(it, sort_key),
                              reverse=not reverse)  # newest first by default
    else:
        sorted_items = sorted(bib_items,
                              key=lambda it: _sort_key_for_item(it, sort_key),
                              reverse=reverse)

    for item in sorted_items:
        data     = item.get("data", item)
        label    = _item_label(data)
        itype    = _c(DIM, data.get("itemType", ""))
        creators = _fmt_creators(data.get("creators", []))
        year     = (data.get("date", "") or "")[:4]
        meta     = f"{creators} ({year})" if creators else year

        # Multi-collection indicator
        item_cols = data.get("collections", [])
        prefix = ""
        if len(item_cols) > 1 and current_collection_key is not None:
            if item_cols[0] != current_collection_key:
                prefix = "→ "

        print(f"{prefix}{_c(CYAN, label)}\t{itype}\t{meta}")


def print_children(children):
    """List item children (attachments/notes): filename TAB type."""
    for child in sorted(children,
                        key=lambda c: (c.get("data", c).get("filename")
                                       or c.get("data", c).get("title")
                                       or "").lower()):
        data     = child.get("data", child)
        filename = data.get("filename") or data.get("title") or data.get("key", "")
        itype    = data.get("itemType", "")
        if itype == "attachment":
            ct = data.get("contentType", "")
            if "pdf" in ct.lower():
                itype = "PDF"
            elif "html" in ct.lower():
                itype = "HTML"
            elif ct:
                itype = ct
        print(f"{filename}\t{_c(DIM, itype)}")


def print_item_info(item):
    """Key-value metadata dump. Priority fields first, then the rest."""
    data = item.get("data", item)

    def row(key, val):
        if val:
            label = _c(BOLD, f"{key}:")
            print(f"{label:<28} {val}")

    row("Title",    data.get("title", ""))
    row("Authors",  _fmt_creators(data.get("creators", []), max_n=10))
    row("Type",     data.get("itemType", ""))
    row("Date",     data.get("date", ""))

    ck = get_citation_key(data)
    if ck:
        row("Citation Key", ck)

    row("Key",      data.get("key", ""))
    row("URL",      data.get("url", ""))
    row("DOI",      data.get("DOI", ""))
    row("ISBN",     data.get("ISBN", ""))
    row("Journal",  data.get("publicationTitle", "") or data.get("journalAbbreviation", ""))
    row("Volume",   data.get("volume", ""))
    row("Issue",    data.get("issue", ""))
    row("Pages",    data.get("pages", ""))
    row("Edition",  data.get("edition", ""))
    row("Publisher", data.get("publisher", ""))
    row("Place",    data.get("place", ""))

    tags = data.get("tags", [])
    if tags:
        row("Tags", ", ".join(t.get("tag", "") for t in tags if t.get("tag")))

    abstract = data.get("abstractNote", "")
    if abstract:
        print(f"{_c(BOLD, 'Abstract:')}")
        print(textwrap.fill(abstract, width=72,
                            initial_indent="  ", subsequent_indent="  "))


def print_find_results(items, collections_map=None):
    """Like print_ls items section but includes collection path per item."""
    for item in items:
        data     = item.get("data", item)
        label    = _item_label(data)
        itype    = _c(DIM, data.get("itemType", ""))
        creators = _fmt_creators(data.get("creators", []))
        year     = (data.get("date", "") or "")[:4]
        meta     = f"{creators} ({year})" if creators else year

        if collections_map:
            item_cols = data.get("collections", [])
            col_path = ""
            if item_cols:
                col_path = collections_map.get(item_cols[0], "")
            if col_path:
                meta = f"{meta}  {_c(DIM, col_path)}"

        print(f"{_c(CYAN, label)}\t{itype}\t{meta}")


def print_tree(collections, parent_key=None, prefix="", depth=None, _current=0,
               zot=None):
    """
    Recursive tree display rooted at parent_key.

    When zot is provided, items are fetched and shown per collection
    (bibliographic items only — not their children/attachments).
    """
    if depth is not None and _current >= depth:
        return

    children_cols = sorted(
        [col for col in collections
         if (col.get("data", col).get("parentCollection") or None) == parent_key],
        key=lambda c: c.get("data", c).get("name", "").lower()
    )

    # Fetch items for this level if zot provided and we're inside a collection
    level_items = []
    if zot is not None and parent_key is not None:
        try:
            raw = zot.everything(zot.collection_items(parent_key))
            level_items = [it for it in raw
                           if not _is_leaf_item(it.get("data", it))]
            level_items = sorted(level_items,
                                 key=lambda it: _item_label(it.get("data", it)).lower())
        except Exception:
            pass

    all_entries = ([("col", c) for c in children_cols]
                   + [("item", it) for it in level_items])

    for idx, (etype, entry) in enumerate(all_entries):
        is_last   = idx == len(all_entries) - 1
        connector = "└── " if is_last else "├── "
        ext       = "    " if is_last else "│   "

        if etype == "col":
            data = entry.get("data", entry)
            name = data.get("name", "")
            print(f"{prefix}{connector}{_c(BOLD, name + '/')}")
            print_tree(collections,
                       parent_key=data.get("key"),
                       prefix=prefix + ext,
                       depth=depth,
                       _current=_current + 1,
                       zot=zot)
        else:
            data     = entry.get("data", entry)
            label    = _item_label(data)
            itype    = _c(DIM, data.get("itemType", ""))
            creators = _fmt_creators(data.get("creators", []))
            year     = (data.get("date", "") or "")[:4]
            meta     = f"{creators} ({year})" if creators else year
            print(f"{prefix}{connector}{_c(CYAN, label)}  {itype}  {meta}")


def error(msg):
    """Print an error to stderr."""
    if sys.stderr.isatty():
        print(f"\033[0;31merror:\033[0m {msg}", file=sys.stderr)
    else:
        print(f"error: {msg}", file=sys.stderr)
