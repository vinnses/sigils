"""
finder.py — find command logic for zotcli.
"""
import sys


def _get_citation_key(item_data):
    if "citationKey" in item_data:
        return item_data["citationKey"]
    extra = item_data.get("extra", "")
    if extra:
        for line in extra.splitlines():
            if line.lower().startswith("citation key:"):
                return line.split(":", 1)[1].strip()
    return None


def _match_field(item_data, field, pattern):
    """Case-insensitive substring match for a specific field."""
    pat = pattern.lower()

    if field is None or field in ("title", "all", None):
        if pat in (item_data.get("title", "") or "").lower():
            return True

    if field is None or field in ("creator", "creators", "all"):
        for c in item_data.get("creators", []):
            name = c.get("lastName", "") or c.get("name", "") or ""
            if pat in name.lower():
                return True

    if field is None or field in ("key", "all"):
        ck = _get_citation_key(item_data)
        if ck and pat in ck.lower():
            return True
        if pat in (item_data.get("key", "") or "").lower():
            return True

    if field in ("doi", "all"):
        if pat in (item_data.get("DOI", "") or "").lower():
            return True

    if field in ("tag", "tags", "all"):
        for t in item_data.get("tags", []):
            if pat in (t.get("tag", "") or "").lower():
                return True

    if field in ("year", "date", "all"):
        date = (item_data.get("date", "") or "")[:4]
        if pat in date:
            return True

    if field in ("type", "itemType", "all"):
        if pat in (item_data.get("itemType", "") or "").lower():
            return True

    if field not in (None, "title", "creator", "creators", "key",
                     "doi", "tag", "tags", "year", "date", "type", "itemType", "all"):
        # Arbitrary field
        val = item_data.get(field, "")
        if val and pat in str(val).lower():
            return True

    return False


def find_in_collection(items, pattern, field=None, tag=None, item_type=None):
    """
    Local case-insensitive substring filter.

    Args:
        items: list of Zotero item dicts
        pattern: search string (None to match all)
        field: field name to search (None = title+creators+citation_key)
        tag: filter by tag (AND logic for multiple calls)
        item_type: filter by itemType
    Returns:
        filtered list of items
    """
    results = []
    for item in items:
        data = item.get("data", item)

        # Tag filter
        if tag is not None:
            item_tags = [t.get("tag", "").lower() for t in data.get("tags", [])]
            if tag.lower() not in item_tags:
                continue

        # Type filter
        if item_type is not None:
            if data.get("itemType", "").lower() != item_type.lower():
                continue

        # Pattern match
        if pattern is not None:
            if not _match_field(data, field, pattern):
                continue

        results.append(item)
    return results


def find_in_library(zot, pattern, field=None, tag=None, item_type=None):
    """
    Server-side search via pyzotero q parameter.
    Returns a list of items.
    """
    params = {}
    if pattern:
        params["q"] = pattern
        if field and field not in (None, "all"):
            # pyzotero qmode: titleCreatorYear, everything
            if field in ("title", "creator", "year"):
                params["qmode"] = "titleCreatorYear"
            else:
                params["qmode"] = "everything"
    if tag:
        params["tag"] = tag
    if item_type:
        params["itemType"] = item_type

    try:
        if params:
            results = zot.everything(zot.items(**params))
        else:
            results = zot.everything(zot.items())
    except Exception as e:
        print(f"error: API search failed: {e}", file=sys.stderr)
        return []

    # Exclude attachments and notes from top-level results
    return [r for r in results
            if r.get("data", r).get("itemType") not in ("attachment", "note")]
