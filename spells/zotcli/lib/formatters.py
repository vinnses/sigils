"""
formatters.py — ANSI-aware output formatters for zotcli.
TTY detection via sys.stdout.isatty(); no color when piped.
"""
import sys
import textwrap

# Color constants — empty strings when not a TTY
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


# ---------------------------------------------------------------------------
# Output functions
# ---------------------------------------------------------------------------

def print_pwd(path):
    print(path)


def print_ls(collections, items):
    """Mixed listing: collections (bold + /) then items."""
    for col in collections:
        data = col.get("data", col)
        print(_c(BOLD, data.get("name", "") + "/"))

    for item in items:
        data     = item.get("data", item)
        label    = _item_label(data)
        itype    = _c(DIM, data.get("itemType", ""))
        creators = _fmt_creators(data.get("creators", []))
        year     = (data.get("date", "") or "")[:4]
        meta     = f"{creators} ({year})" if creators else year
        print(f"{_c(CYAN, label)}\t{itype}\t{meta}")


def print_children(children):
    """List item children (attachments/notes): filename TAB type."""
    for child in children:
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

    # Priority fields
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


def print_tree(collections, parent_key=None, prefix=""):
    """Recursive tree display rooted at parent_key."""
    children = [
        col for col in collections
        if (col.get("data", col).get("parentCollection") or None) == parent_key
    ]
    for i, col in enumerate(children):
        data    = col.get("data", col)
        name    = data.get("name", "")
        is_last = i == len(children) - 1
        connector = "└── " if is_last else "├── "
        print(f"{prefix}{connector}{_c(BOLD, name + '/')}")
        ext = "    " if is_last else "│   "
        print_tree(collections, parent_key=data.get("key"), prefix=prefix + ext)


def error(msg):
    """Print an error to stderr."""
    print(f"{RED}error:{NC} {msg}" if RED else f"error: {msg}", file=sys.stderr)
