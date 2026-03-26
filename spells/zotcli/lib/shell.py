"""
shell.py — interactive Python shell with pre-loaded Zotero context.
Launched when zotcli is called with no arguments.
"""
import code
import os
import sys


def main():
    spell_dir = os.environ.get(
        "SPELL_DIR",
        os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    )
    sys.path.insert(0, os.path.join(spell_dir, "lib"))

    try:
        import pyzotero
    except ImportError:
        print("pyzotero is not installed. Run: make install", file=sys.stderr)
        sys.exit(1)

    from client import get_zotero
    import helpers

    zot = get_zotero()

    # Build namespace with zot, pyzotero, and all public helpers
    namespace = {"zot": zot, "pyzotero": pyzotero}
    namespace.update(
        {name: getattr(helpers, name) for name in dir(helpers) if not name.startswith("_")}
    )

    banner = """\
zotcli interactive shell
========================
Available objects:
  zot       — authenticated Zotero instance (pyzotero)
  pyzotero  — pyzotero module

Available helpers (from helpers.py):
  print_collection_tree(collections)
  print_collection_flat(collections)
  print_items_table(items)
  print_item_info(item)
  print_attachments(attachments)
  find_collection(zot_or_cache, query)
  find_item(zot_or_cache, query)

Example:
  cols = zot.everything(zot.collections()); print_collection_tree(cols)
"""

    code.interact(banner=banner, local=namespace, exitmsg="")


if __name__ == "__main__":
    main()
