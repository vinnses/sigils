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


def find_in_db(conn, pattern, field=None, collection_key=None,
               tags=None, item_type=None):
    """
    SQL-backed local search against the SQLite database.

    Returns items in the same pyzotero-shaped list format as
    find_in_collection() and find_in_library().

    Args:
        conn:           open sqlite3 connection from db.open_db()
        pattern:        substring to search (None = match all)
        field:          field name to restrict search (None = title+creator+key)
        collection_key: restrict to a specific collection (None = whole library)
        tags:           list of tag strings (AND logic)
        item_type:      filter by itemType string
    """
    import db as _db

    clauses = ["i.item_type NOT IN ('attachment', 'note')"]
    params  = []

    if item_type:
        clauses.append("i.item_type = ?")
        params.append(item_type.lower())

    if tags:
        for tag in tags:
            clauses.append(
                "EXISTS (SELECT 1 FROM tags t WHERE t.item_key = i.key"
                " AND LOWER(t.tag) = ?)"
            )
            params.append(tag.lower())

    if collection_key:
        clauses.append(
            "EXISTS (SELECT 1 FROM item_collections ic"
            " WHERE ic.item_key = i.key AND ic.collection_key = ?)"
        )
        params.append(collection_key)

    if pattern:
        pat = f"%{pattern.lower()}%"
        if field in (None, "title"):
            clauses.append("LOWER(COALESCE(i.title, '')) LIKE ?")
            params.append(pat)
        elif field in ("creator", "creators"):
            # JSON extract falls back to substring on data_json
            clauses.append("LOWER(i.data_json) LIKE ?")
            params.append(f"%\"lastName\": \"%{pattern.lower()}%\"%")
        elif field in ("key",):
            clauses.append(
                "(LOWER(COALESCE(i.citation_key,'')) LIKE ? OR LOWER(i.key) LIKE ?)"
            )
            params += [pat, pat]
        elif field in ("tag", "tags"):
            clauses.append(
                "EXISTS (SELECT 1 FROM tags t WHERE t.item_key = i.key"
                " AND LOWER(t.tag) LIKE ?)"
            )
            params.append(pat)
        elif field in ("year", "date"):
            clauses.append(
                "LOWER(json_extract(i.data_json, '$.date')) LIKE ?"
            )
            params.append(pat)
        else:
            # Generic field: substring on data_json (covers all fields)
            clauses.append("LOWER(i.data_json) LIKE ?")
            params.append(pat)

    where = " AND ".join(clauses)
    sql   = f"""
        SELECT i.key, i.version, i.data_json
          FROM items i
         WHERE {where}
         ORDER BY i.title
    """
    rows = conn.execute(sql, params).fetchall()
    return [
        {"key": r["key"], "version": r["version"],
         "data": __import__("json").loads(r["data_json"])}
        for r in rows
    ]


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
