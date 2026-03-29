#!/usr/bin/env python3
"""
shell_py.py — Python REPL / -c / script execution for `zotcli py`.

Three modes sharing a single build_namespace():
  zotcli py              → interactive REPL (stdlib code.interact)
  zotcli py -c "code"    → execute inline code
  zotcli py script.py    → execute a script file

Auto-imports are loaded from config/imports.py.
"""
import code
import os
import sys

SPELL_DIR = os.environ.get(
    "SPELL_DIR",
    os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
)
sys.path.insert(0, os.path.join(SPELL_DIR, "lib"))


def build_namespace():
    """Build the shared namespace with Zotero objects and auto-imports."""
    from client    import get_zotero
    import cache   as _cache
    import navigator as _nav

    zot         = get_zotero()
    collections = _cache.get_collections()

    ns = {
        "zot":         zot,
        "collections": collections,
    }

    # Import pyzotero module itself
    try:
        import pyzotero as _pyzotero
        ns["pyzotero"] = _pyzotero
    except ImportError:
        pass

    # Load config/imports.py
    imports_file = os.path.join(SPELL_DIR, "config", "imports.py")
    if os.path.isfile(imports_file):
        try:
            with open(imports_file) as f:
                src = f.read()
            exec(compile(src, imports_file, "exec"), ns)
        except Exception as e:
            print(f"Warning: could not load {imports_file}: {e}", file=sys.stderr)

    # In-memory navigator (mirrors CLI navigation, does not persist state)
    class Navigator:
        def __init__(self):
            self.key    = None
            self.path   = "^"
            self._prev_key  = None
            self._prev_path = None

        def cd(self, path="^"):
            import navigator as nav
            try:
                new_key, new_path, new_item_key, _ = nav.resolve_path(
                    self.key, self.path, path, collections
                )
            except ValueError as e:
                print(f"cd: {e}")
                return self
            self._prev_key  = self.key
            self._prev_path = self.path
            self.key  = new_key
            self.path = new_path
            print(new_path)
            return self

        def pwd(self):
            print(self.path)
            return self.path

        def ls(self, ref=None):
            import navigator  as nav
            import formatters as fmt

            if ref is None:
                sub_cols = nav.get_children(collections, self.key)
                items    = self._items(self.key)
                fmt.print_ls(sub_cols, items)
                return

            try:
                col_key, _, _, _ = nav.resolve_path(
                    self.key, self.path, ref, collections
                )
                sub_cols = nav.get_children(collections, col_key)
                items    = self._items(col_key)
                fmt.print_ls(sub_cols, items)
            except ValueError:
                items = self._items(self.key)
                import navigator as nav2
                match = nav2._find_item_by_ref(items, ref)
                if match:
                    children = zot.children(match.get("data", match)["key"])
                    fmt.print_children(children)
                else:
                    print(f"ls: '{ref}' not found")

        def tree(self):
            import formatters as fmt
            fmt.print_tree(collections, parent_key=self.key)

        def cat(self, ref):
            import formatters as fmt
            import navigator  as nav
            items = self._items(self.key)
            item_ref, child_ref = (ref.split(":", 1) + [None])[:2]
            match = nav._find_item_by_ref(items, item_ref)
            if match is None:
                print(f"cat: '{item_ref}' not found")
                return
            if child_ref is None:
                fmt.print_item_info(match)
                return
            children = zot.children(match.get("data", match)["key"])
            from commands import _find_child
            child = _find_child(children, child_ref)
            if child is None:
                print(f"cat: child '{child_ref}' not found")
                return
            fmt.print_item_info(child)

        def _items(self, col_key):
            if col_key is None:
                return []
            try:
                return zot.everything(zot.collection_items(col_key))
            except Exception:
                return zot.collection_items(col_key)

        def __repr__(self):
            return f"Navigator(path={self.path!r})"

    ns["n"] = Navigator()
    return ns


def _run_interactive(ns):
    """Start stdlib interactive REPL with readline tab completion."""
    banner = """\
zotcli py — interactive Zotero shell
=====================================
Available:
  zot          — authenticated Zotero instance (pyzotero)
  pyzotero     — pyzotero module
  collections  — full collection list
  n            — in-memory Navigator (n.cd, n.ls, n.pwd, n.tree, n.cat)

Example:
  n.cd("^/Books"); n.ls()
"""
    try:
        import readline
        import rlcompleter
        readline.set_completer(rlcompleter.Completer(ns).complete)
        readline.parse_and_bind("tab: complete")
    except ImportError:
        pass

    code.interact(banner=banner, local=ns, exitmsg="")


def main():
    args = sys.argv[1:]

    # Inline execution: -c "code string"
    if args and args[0] == "-c":
        if len(args) < 2:
            print("Usage: zotcli py -c \"<code>\"", file=sys.stderr)
            sys.exit(1)
        ns = build_namespace()
        exec(compile(args[1], "<zotcli-c>", "exec"), ns)
        return

    # Script file execution
    if args and not args[0].startswith("-"):
        script_path = args[0]
        if not os.path.isfile(script_path):
            print(f"error: script not found: {script_path}", file=sys.stderr)
            sys.exit(1)
        ns = build_namespace()
        with open(script_path) as f:
            src = f.read()
        exec(compile(src, script_path, "exec"), ns)
        return

    # Interactive REPL
    ns = build_namespace()
    _run_interactive(ns)


if __name__ == "__main__":
    main()
