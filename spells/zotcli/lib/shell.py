"""
shell.py — interactive Python shell with pre-loaded Zotero context.
Launched when zotcli is called with no arguments.
State changes in the shell are in-memory only; they do not persist to
data/state.json, keeping exploration independent from CLI navigation state.
"""
import code
import os
import sys


class Navigator:
    """
    In-memory filesystem-like navigator for the interactive shell.
    Mirrors the CLI commands but operates on an in-memory state.
    """

    def __init__(self, zot, collections):
        self.zot         = zot
        self.collections = collections
        self.key         = None   # current collection key (None = root)
        self.path        = "~"
        self._prev_key   = None
        self._prev_path  = None

    # ------------------------------------------------------------------

    def cd(self, path="~"):
        """Navigate to path. Supports ~, .., -, relative, absolute."""
        import navigator as nav
        try:
            new_key, new_path = nav.resolve_path(
                self.key, self.path, path, self.collections,
                self._prev_key, self._prev_path,
            )
        except ValueError as e:
            print(f"cd: {e}")
            return self
        self._prev_key  = self.key
        self._prev_path = self.path
        self.key        = new_key
        self.path       = new_path
        print(new_path)
        return self

    def pwd(self):
        """Print current path."""
        print(self.path)
        return self.path

    def ls(self, ref=None):
        """List current collection, or a sub-collection / item children."""
        import navigator  as nav
        import formatters as fmt

        if ref is None:
            sub_cols = nav.get_children(self.collections, self.key)
            items    = self._items(self.key)
            fmt.print_ls(sub_cols, items)
            return

        # Try as collection path first
        try:
            target_key, _ = nav.resolve_path(
                self.key, self.path, ref, self.collections
            )
            sub_cols = nav.get_children(self.collections, target_key)
            items    = self._items(target_key)
            fmt.print_ls(sub_cols, items)
        except ValueError:
            # Fall back to item children
            items = self._items(self.key)
            import commands as cmd
            try:
                item     = cmd._find_item(items, ref)
                children = self.zot.children(item.get("data", item)["key"])
                fmt.print_children(children)
            except ValueError as e:
                print(f"ls: {e}")

    def tree(self):
        """Print collection tree from current position."""
        import formatters as fmt
        fmt.print_tree(self.collections, parent_key=self.key)

    def cat(self, ref):
        """Show item metadata (or child metadata with item:child syntax)."""
        import formatters as fmt
        import commands   as cmd
        items = self._items(self.key)
        item_ref, child_ref = cmd._parse_ref(ref)
        try:
            item = cmd._find_item(items, item_ref)
        except ValueError as e:
            print(f"cat: {e}")
            return
        if child_ref is None:
            fmt.print_item_info(item)
            return
        children = self.zot.children(item.get("data", item)["key"])
        child    = cmd._find_child(children, child_ref)
        if child is None:
            print(f"cat: child '{child_ref}' not found")
            return
        fmt.print_item_info(child)

    # ------------------------------------------------------------------

    def _items(self, col_key):
        if col_key is None:
            return []
        try:
            return self.zot.everything(self.zot.collection_items(col_key))
        except Exception:
            return self.zot.collection_items(col_key)

    def __repr__(self):
        return f"Navigator(path={self.path!r})"


# ---------------------------------------------------------------------------

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

    from client     import get_zotero
    import cache        as _cache
    import formatters   as fmt
    import navigator    as nav

    zot         = get_zotero()
    collections = _cache.get_collections()
    n           = Navigator(zot, collections)

    namespace = {
        "zot":         zot,
        "pyzotero":    pyzotero,
        "n":           n,
        "collections": collections,
        "fmt":         fmt,
        "nav":         nav,
    }

    banner = """\
zotcli interactive shell
========================
Available objects:
  zot          — authenticated Zotero instance (pyzotero)
  pyzotero     — pyzotero module
  n            — Navigator (in-memory, does not persist to state.json)
  collections  — full collection list (list of dicts)
  fmt          — formatters module
  nav          — navigator module

Navigator methods:
  n.cd("path")   n.pwd()   n.ls()   n.tree()   n.cat("ref")

Example:
  n.cd("~/1.Books"); n.ls()
"""
    _start_repl(namespace, banner)


def _start_repl(namespace, banner):
    """Try IPython → ptpython → stdlib code.interact (in that order)."""
    # IPython
    try:
        from IPython import start_ipython
        # start_ipython (not embed) to respect user's IPython config and avoid
        # namespace bugs with closures. argv=[] prevents parsing sys.argv.
        start_ipython(argv=[], user_ns=namespace)
        return
    except ImportError:
        pass

    # ptpython
    try:
        from ptpython.repl import embed as pt_embed
        pt_embed(globals=namespace, locals=namespace)
        return
    except ImportError:
        pass

    # Stdlib fallback — add readline tab completion
    try:
        import readline
        import rlcompleter
        readline.set_completer(rlcompleter.Completer(namespace).complete)
        readline.parse_and_bind("tab: complete")
    except ImportError:
        pass

    code.interact(banner=banner, local=namespace, exitmsg="")


if __name__ == "__main__":
    main()
