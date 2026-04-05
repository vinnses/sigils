# zotcli v3 — Implementation Plan

## Status

- [x] Implementado em 2026-04-05
- [x] Branch de trabalho: `sigils-zotcli-v3` (`35890e8`)
- [x] Consolidado no repositório em `sigils-zotcli-integration` (`6befa3d`)
- [x] Escopo entregue:
  contrato canônico com `^`, `off` funcional no shell wrapper, README/Makefile alinhados ao CLI real, `check` target, teste shell para hook/env, e spell reabilitado no workspace
- [ ] Validação com credenciais reais do Zotero continua sendo a única lacuna não coberta por testes offline

> Spell for the `sigils` repository.
> Filesystem-like CLI for navigating and querying a Zotero library via `pyzotero`.
> Works with or without Zotero Desktop (web API).

This document is the sole specification for Claude Code. It supersedes all
prior plans (v1, v2) and the existing codebase on the
`claude/zotcli-implementation-*` branch. Reuse existing code where logic is
unchanged; rewrite everything else.

---

## Table of Contents

1. [Concepts & Terminology](#1-concepts--terminology)
2. [Modes of Use](#2-modes-of-use)
3. [Root Symbol](#3-root-symbol)
4. [Navigation Model](#4-navigation-model)
5. [Command Reference](#5-command-reference)
6. [Visual Mode (PS1 Hook)](#6-visual-mode-ps1-hook)
7. [Configuration System](#7-configuration-system)
8. [Cache System](#8-cache-system)
9. [State System](#9-state-system)
10. [Dependency Management](#10-dependency-management)
11. [File Structure](#11-file-structure)
12. [Module Specifications](#12-module-specifications)
13. [Bash Entrypoint](#13-bash-entrypoint)
14. [Completions](#14-completions)
15. [Ordering & Sorting](#15-ordering--sorting)
16. [Multi-collection Items](#16-multi-collection-items)
17. [Unfiled Items](#17-unfiled-items)
18. [Error Handling](#18-error-handling)
19. [Tests](#19-tests)
20. [.gitignore](#20-gitignore)
21. [README.md](#21-readmemd)
22. [Implementation Notes for Claude Code](#22-implementation-notes-for-claude-code)

---

## 1. Concepts & Terminology

The Zotero library is modeled as a tree with three levels of depth:

```
^ (root)
├── Collection/
│   ├── Subcollection/
│   │   ├── item
│   │   │   ├── attachment (child)
│   │   │   └── note (child)
│   │   └── item
│   └── item
└── Collection/
    └── ...
```

- **Collection**: a container (directory). Can be nested. Navigable with `cd`.
- **Item**: a bibliographic reference (book, paper, etc). Lives inside collections.
  Items are also navigable with `cd` — entering an item shows its children.
- **Child**: an attachment (PDF, snapshot), note, or link that belongs to an item.
  Children are leaf nodes. Not navigable with `cd`.
- **Unfiled item**: an item with no collections (`data.collections == []`).
  Only visible at root via `ls --unfiled`.

State tracks two levels:
- `collection_key`: which collection we're in (null = root).
- `item_key`: which item we're inside (null = not inside an item).

When `item_key` is set, `ls` shows children, `cat` shows child metadata,
and `cd ..` returns to the parent collection.

---

## 2. Modes of Use

### Mode 1 — Direct commands

```
zotcli <command> [--flags] [args]
```

Each invocation is independent. State persists in `data/state.json`.
Works from any terminal, no setup required beyond `zotcli connect`.

### Mode 2 — Visual mode (automatic)

Any `zotcli` command automatically activates a PS1 hook showing the current
Zotero path and sync age. The hook persists for the life of the shell session.
`zotcli off` removes the PS1 hook and resets navigation state.

See [Section 6](#6-visual-mode-ps1-hook) for implementation details.

### Mode 3 — Python REPL

```
zotcli py                       # interactive REPL
zotcli py -c "code string"      # execute inline code
zotcli py script.py             # execute a script file
```

Auto-imports are loaded from `config/imports.py`. Users can add arbitrary
imports there (e.g. `import pandas as pd`).

See [Section 12, shell_py.py](#shell_pypy) for implementation details.

---

## 3. Root Symbol

**`^`** represents the Zotero library root, replacing `~` to avoid bash
tilde expansion.

- `^` — root (no quoting needed)
- `^/1.Books` — absolute path from root
- `^/1.Books/AI` — nested absolute path
- `1.Books` — relative to current location
- `..` — parent (collection or item → collection)
- `-` — previous location

`^` is safe in bash: it is not expanded by the shell in argument position.
All output, state files, completions, and documentation use `^`.

---

## 4. Navigation Model

The navigation model has two levels: collections and items.

### Collection navigation (standard)

```
zotcli cd 1.Books         # enter a collection
zotcli cd ^/2.Papers/NLP  # absolute path
zotcli cd ..              # go up
zotcli cd -               # previous location
zotcli cd                 # go to root
```

State: `collection_key` is set, `item_key` is null.

### Item navigation

```
zotcli cd jurafsky2026    # enter an item (from within its collection)
```

State: `collection_key` stays as-is, `item_key` is set.

Inside an item:
- `ls` shows children (attachments, notes).
- `cat <child>` shows child metadata.
- `cd ..` returns to the parent collection (clears `item_key`).
- `cd` to root also clears `item_key`.

`cd` into an item is only valid when the item is in the current collection.
You cannot `cd` into a child (children are leaves).

### The `:` shortcut

The `:` separator allows accessing children without `cd`-ing into the item:

```
zotcli cat jurafsky2026:0-FullBook    # child metadata, no cd
zotcli ls jurafsky2026                # list children, no cd
zotcli get jurafsky2026:0-FullBook    # download attachment, no cd
```

`:` is a convenience — it does NOT change navigation state. The left side
resolves as an item in the current collection, the right side as a child
of that item.

### Name resolution

Items and children are resolved by **exact match** only:

1. Citation key (e.g. `jurafsky2026`) — field `citationKey` or `extra`
2. Item key (e.g. `ABC123`) — field `data.key`
3. Exact title (e.g. `"Speech and language processing..."`)

No substring matching. No fuzzy logic. If the reference doesn't match
exactly, error with suggestion to use `find`.

Children are resolved by:
1. Exact filename (e.g. `0-FullBook`)
2. Exact title
3. Child key

---

## 5. Command Reference

### Navigation

| Command | Description |
|---|---|
| `zotcli cd [path]` | Navigate. Supports `^`, `^/path`, `..`, `-`, relative. No args = root. |
| `zotcli pwd` | Print current path (collection + item if inside one). |
| `zotcli tree [--depth N]` | Recursive tree from current level. Default depth: unlimited. |

### Listing

| Command | Description |
|---|---|
| `zotcli ls` | List contents of current level (collections+items, or children if inside item). |
| `zotcli ls <path>` | List contents of a collection or item without entering it. |
| `zotcli ls --sort <field>` | Sort by: `name` (default), `date`, `type`, `creator`. |
| `zotcli ls --reverse` | Reverse sort order. |
| `zotcli ls --unfiled` | At root only: list items not in any collection. |

### Reading

| Command | Description |
|---|---|
| `zotcli cat <ref>` | Show metadata for an item or child. Exact match only. |
| `zotcli cat <item>:<child>` | Show child metadata (shortcut, no cd needed). |

### Searching

| Command | Description |
|---|---|
| `zotcli find <pattern>` | Search items. Default scope: current collection. Default fields: title, creators, citation key. |
| `zotcli find <pattern> --field <f>` | Search a specific field (title, creator, tag, doi, year, key, etc). |
| `zotcli find <pattern> --scope library` | Search entire library (uses pyzotero server-side search). |
| `zotcli find --tag <tag>` | Filter by tag. Multiple `--tag` flags = AND. |
| `zotcli find --type <itemType>` | Filter by item type (book, journalArticle, etc). |

Output format: same as `ls` (label, type, creator, year). Results show which
collection each item is in when `--scope library`.

### Exporting

| Command | Description |
|---|---|
| `zotcli get <item>` | Export in default format (configurable, default: `bibtex`). |
| `zotcli get <item> --bibtex` | Export as BibTeX to stdout. |
| `zotcli get <item> --json` | Export as JSON to stdout. |
| `zotcli get <item> --bib [--style <csl>]` | Export formatted bibliography. |
| `zotcli get <item>:<child>` | Download attachment to current working directory. |
| `zotcli get <item>:<child> -o <path>` | Download attachment to specified path. |

### Setup & Maintenance

| Command | Description |
|---|---|
| `zotcli connect` | Interactive credential setup (library ID + API key). |
| `zotcli sync` | Force-refresh cache from API. |
| `zotcli off` | Deactivate visual mode + reset navigation state to root. |
| `zotcli config` | Print current effective configuration (defaults + overrides). |
| `zotcli config <key> <value>` | Set a configuration value (dot-notation). |

### Python

| Command | Description |
|---|---|
| `zotcli py` | Interactive Python REPL with auto-imports. |
| `zotcli py -c "<code>"` | Execute inline Python code with auto-imports namespace. |
| `zotcli py <script.py>` | Execute a script file with auto-imports namespace. |

### Global Flags

| Flag | Description |
|---|---|
| `--fresh` | Bypass cache for this command, fetch directly from API. |

---

## 6. Visual Mode (PS1 Hook)

### Activation

Visual mode activates automatically on the first `zotcli` command in a
shell session. The wrapper shell function (defined in `completions/bash/zotcli.bash`)
checks for `ZOTCLI_VISUAL` env var:
- If unset: install the PROMPT_COMMAND hook, set `ZOTCLI_VISUAL=1`, then
  run the command.
- If already set: just run the command.

### PS1 Display

The hook prints a line ABOVE the existing prompt to stderr:

```
(zot) ^/1.Books  [synced 12m ago]
user@host:~/projects $
```

Implementation: a `PROMPT_COMMAND` function that:
1. Preserves the previous exit status (`local prev=$?`).
2. Reads `ZOTCLI_PATH` env var (set by zotcli commands that modify state).
3. Reads `ZOTCLI_SYNC_AGE` env var (set by cache operations).
4. Prints the info line to stderr (not stdout, to avoid interfering with pipes).
5. Returns the preserved exit status.

**Critical**: the hook must NOT spawn subprocesses or read files. All data
comes from environment variables set by the `zotcli` commands themselves.
This ensures zero overhead on every prompt.

### Deactivation

`zotcli off`:
1. Unsets `ZOTCLI_VISUAL`, `ZOTCLI_PATH`, `ZOTCLI_SYNC_AGE`.
2. Removes `__zotcli_hook` from `PROMPT_COMMAND`.
3. Resets navigation state (writes root state to `data/state.json`).

Also deactivated by closing the terminal (env vars don't persist).

---

## 7. Configuration System

### Files

- `config/zotcli.defaults.yaml` — shipped with the spell, committed to git.
  Contains all keys with their default values. Read-only reference.
- `config/zotcli.yaml` — user overrides, gitignored. Created by
  `zotcli config <key> <value>` or manually.

### Default Configuration

```yaml
# Display
ls:
  default_sort: name       # name | date | type | creator
  sort_reverse: false

# Export
get:
  default_format: bibtex   # bibtex | json | bib
  bib_style: apa           # any CSL style name

# Cache
cache:
  ttl_seconds: 3600        # 1 hour

# Visual mode
visual:
  enabled: true            # set to false to disable PS1 hook entirely
  show_sync_age: true
```

### Merge Logic

`config.py` loads defaults, then overlays user config (deep merge).
Environment variables can also override: `ZOTCLI_GET__DEFAULT_FORMAT=json`
(double underscore = nested key separator).

Priority (lowest → highest):
1. `zotcli.defaults.yaml`
2. `zotcli.yaml`
3. Environment variables (`ZOTCLI_*`)
4. CLI flags (`--bibtex`, `--sort`, etc)

### `zotcli config` command

- `zotcli config` — print effective merged config as YAML.
- `zotcli config ls.default_sort date` — set a value in `zotcli.yaml`.
  Creates file if needed. Preserves existing values.
- `zotcli config ls.default_sort` — print a single value.

### Library

Use `pyyaml` for reading/writing.

---

## 8. Cache System

### File

`data/cache.json`:

```json
{
  "collections": [ ... ],
  "updated_at": "2026-03-26T02:30:00+00:00"
}
```

### Behavior

- Caches the full collection tree (needed for path resolution, tree,
  completions, and `ls` of collections).
- Items are NOT cached globally — fetched per-collection on demand.
  Libraries can be very large; caching all items is impractical.
- TTL: configurable via `cache.ttl_seconds` (default 3600 = 1 hour).
- Auto-refresh: if cache is stale or missing, any command that needs
  collections fetches them transparently.
- `--fresh` flag: bypasses cache for that single invocation.
- `zotcli sync`: invalidates cache and forces a full refresh.

### Sync age tracking

After every cache write, the Python commands output a `__ZOTCLI_ENV__`
line for `ZOTCLI_SYNC_AGE` with a human-readable string (e.g. "12m ago").
The shell wrapper exports it. The PS1 hook reads it.

---

## 9. State System

### File

`data/state.json`:

```json
{
  "collection_key": "KJUL4W7I",
  "collection_path": "^/1.Books",
  "item_key": null,
  "item_label": null,
  "previous_collection_key": "C6F4VX2W",
  "previous_collection_path": "^/0.Inbox",
  "previous_item_key": null
}
```

### Fields

- `collection_key`: current collection (null = root).
- `collection_path`: human-readable path string for display.
- `item_key`: current item if cd'd into one (null = not inside item).
- `item_label`: display label of current item (citation key or title).
- `previous_*`: for `cd -` support.

### Writes

Atomic: write to temp file, `os.replace()` to state file.
Updated by `cd` and `zotcli off` (reset to root).

### Path env var

After every state write, the full display path is emitted as a
`__ZOTCLI_ENV__ZOTCLI_PATH=...` line. Format:

- Collection only: `^/1.Books`
- Inside item: `^/1.Books/jurafsky2026`

---

## 10. Dependency Management

### `pyproject.toml`

```toml
[project]
name = "zotcli-spell"
version = "0.3.0"
requires-python = ">=3.10"
dependencies = [
    "pyzotero",
    "pyyaml",
]

[project.optional-dependencies]
dev = ["pytest"]
```

### Virtual environment

Managed by `uv` at `spells/zotcli/.venv/` (gitignored).

The bash entrypoint detects the venv and uses its Python:
```bash
VENV="$SPELL_DIR/.venv"
if [[ -d "$VENV" ]]; then
  PYTHON="$VENV/bin/python3"
else
  PYTHON="python3"
fi
```

### Makefile

```makefile
SHELL := /bin/bash
SPELL_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

.PHONY: install install-dev test clean purge

install:
	cd "$(SPELL_DIR)" && uv sync

install-dev:
	cd "$(SPELL_DIR)" && uv sync --dev

test:
	cd "$(SPELL_DIR)" && uv run python tests/smoke.py

clean:
	rm -f "$(SPELL_DIR)/data/cache.json" "$(SPELL_DIR)/data/state.json"

purge: clean
	rm -rf "$(SPELL_DIR)/.venv"
```

---

## 11. File Structure

```
spells/zotcli/
├── bin/zotcli                      # bash entrypoint (raw binary)
├── lib/
│   ├── client.py                   # pyzotero init + credential loading
│   ├── state.py                    # navigation state read/write
│   ├── navigator.py                # path resolution, tree traversal
│   ├── formatters.py               # ANSI output formatting
│   ├── cache.py                    # collection cache (JSON, TTL)
│   ├── commands.py                 # subcommand dispatcher and all handlers
│   ├── config.py                   # configuration loader (YAML)
│   ├── finder.py                   # find command logic
│   └── shell_py.py                 # Python REPL / -c / script execution
├── config/
│   ├── credentials.env             # API credentials (gitignored)
│   ├── zotcli.defaults.yaml        # default config (committed)
│   ├── zotcli.yaml                 # user overrides (gitignored)
│   └── imports.py                  # auto-imports for `zotcli py` (committed)
├── data/
│   ├── state.json                  # navigation state (gitignored)
│   └── cache.json                  # cached collections (gitignored)
├── completions/bash/
│   └── zotcli.bash                 # wrapper function + completions + hook
├── tests/
│   └── smoke.py
├── pyproject.toml
├── Makefile
└── README.md
```

---

## 12. Module Specifications

### `client.py`

Unchanged from v2 except venv Python is used (handled by entrypoint).
- `get_zotero()` returns `pyzotero.zotero.Zotero`.
- Credentials from `config/credentials.env` (KEY=value, no python-dotenv).
- Env vars override file values.
- Missing credentials → actionable error pointing to `zotcli connect`.

### `state.py`

Expanded to track item navigation:

```python
_DEFAULT = {
    "collection_key": None,
    "collection_path": "^",
    "item_key": None,
    "item_label": None,
    "previous_collection_key": None,
    "previous_collection_path": None,
    "previous_item_key": None,
}

def read_state() -> dict
def write_state(**fields)       # atomic write
def reset_state()               # write defaults (root)
def full_path(state) -> str     # "^/1.Books" or "^/1.Books/jurafsky2026"
```

### `navigator.py`

Expanded with item navigation:

```python
def resolve_path(current_key, current_path, path_string, collections,
                 items=None, item_key=None,
                 previous_key=None, previous_path=None,
                 previous_item_key=None):
    """
    Returns (collection_key, collection_path, item_key, item_label).
    
    When items is provided and a path segment matches an item (but not
    a subcollection), the resolution enters the item.
    .. from inside an item returns to the parent collection.
    """

def get_children(collections, parent_key) -> list
def get_parent_key(collections, child_key) -> key|None
def build_path(collections, key) -> str
def get_collection_by_key(collections, key) -> dict|None
```

### `cache.py`

From v2 plus:
- `sync_age_human() -> str` — "12m ago", "2h ago", "just now", "unknown".

### `config.py`

New module:
```python
def load_config() -> dict          # defaults + user + env
def get_value(config, dotpath)     # e.g. 'ls.default_sort'
def set_value(dotpath, value)      # writes to zotcli.yaml
def print_config(config)           # YAML to stdout
```

Env var override: `ZOTCLI_LS__DEFAULT_SORT=date` (prefix + double underscore).

### `finder.py`

New module:
```python
def find_in_collection(items, pattern, field=None) -> list
    """Local case-insensitive substring filter."""

def find_in_library(zot, pattern, field=None, tag=None, item_type=None) -> list
    """Server-side search via pyzotero q parameter."""
```

### `formatters.py`

From v2 with:
- Root symbol `^` everywhere.
- `→` prefix for multi-collection items (see Section 16).
- `print_ls()` accepts `sort_key` and `reverse`.
- `print_find_results()` — like `ls` but includes collection path per item.
- All pure functions, TTY-aware colors.

### `commands.py`

All handlers. Key changes from v2:
- `cmd_cd`: handles item navigation. Sets `item_key` in state.
- `cmd_ls`: when inside item, lists children. Respects `--sort`, `--reverse`, `--unfiled`.
- `cmd_cat`: strict exact match only. No substring fallback.
- `cmd_get`: respects config `get.default_format`.
- `cmd_find`: new. Delegates to `finder.py`.
- `cmd_off`: resets state, outputs deactivation env vars.
- `cmd_config`: prints or sets config.

**Env var export protocol**: commands that modify state emit lines to stdout:
```
__ZOTCLI_ENV__ZOTCLI_PATH=^/1.Books
__ZOTCLI_ENV__ZOTCLI_SYNC_AGE=12m ago
```
The shell wrapper parses these and `export`s them.

### <a name="shell_pypy"></a>`shell_py.py`

Three modes sharing a single `build_namespace()`:

```python
def build_namespace():
    ns = {}
    ns["zot"] = get_zotero()
    ns["pyzotero"] = pyzotero_module
    ns["collections"] = get_collections()
    # Load config/imports.py
    imports_file = os.path.join(SPELL_DIR, "config", "imports.py")
    if os.path.isfile(imports_file):
        exec(compile(open(imports_file).read(), imports_file, "exec"), ns)
    ns["n"] = Navigator(zot, collections)  # in-memory navigator
    return ns
```

Interactive mode: `code.interact()` with readline tab completion.
`-c` mode: `exec(code, namespace)`.
Script mode: `exec(open(path).read(), namespace)`.

---

## 13. Bash Entrypoint

### Architecture

Two components work together:

1. **`bin/zotcli`** — the raw binary (bash script). Routes subcommands to Python.
   Called by `command zotcli` (bypassing the wrapper).

2. **`completions/bash/zotcli.bash`** — defines:
   - `zotcli()` shell function wrapper (captures env var exports, manages visual mode)
   - `zot()` alias function
   - `__zotcli_hook()` PROMPT_COMMAND function
   - `_zotcli()` completion function

The sigils init system (`init/env.bash`) sources all
`spells/*/completions/bash/*.bash` files, which installs the wrapper
automatically.

### `bin/zotcli` (raw binary)

```bash
#!/bin/bash
set -o pipefail

_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"
SPELL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VENV="$SPELL_DIR/.venv"
[[ -d "$VENV" ]] && PYTHON="$VENV/bin/python3" || PYTHON="python3"

FRESH=false; ARGS=()
for arg in "$@"; do
  [[ "$arg" == "--fresh" ]] && FRESH=true || ARGS+=("$arg")
done

SUBCOMMAND="${ARGS[0]:-}"
SUBARGS=("${ARGS[@]:1}")
export SPELL_DIR ZOTCLI_FRESH="$FRESH"

case "$SUBCOMMAND" in
  py)  exec "$PYTHON" "$SPELL_DIR/lib/shell_py.py" "${SUBARGS[@]}" ;;
  "")  echo "Usage: zotcli <command> [args]. Try 'zotcli --help'." >&2; exit 1 ;;
  *)   exec "$PYTHON" "$SPELL_DIR/lib/commands.py" "$SUBCOMMAND" "${SUBARGS[@]}" ;;
esac
```

### Shell wrapper (in `completions/bash/zotcli.bash`)

```bash
zotcli() {
    # Special handling for 'off'
    if [[ "${1:-}" == "off" ]]; then
        command zotcli off "${@:2}"
        unset ZOTCLI_VISUAL ZOTCLI_PATH ZOTCLI_SYNC_AGE
        PROMPT_COMMAND="${PROMPT_COMMAND//__zotcli_hook;/}"
        return 0
    fi

    local output exitcode
    output=$(command zotcli "$@")
    exitcode=$?

    # Separate env exports from display output
    local line
    while IFS= read -r line; do
        if [[ "$line" == __ZOTCLI_ENV__* ]]; then
            export "${line#__ZOTCLI_ENV__}"
        else
            printf '%s\n' "$line"
        fi
    done <<< "$output"

    # Auto-activate visual mode
    if [[ -z "${ZOTCLI_VISUAL:-}" ]]; then
        export ZOTCLI_VISUAL=1
        if [[ ";${PROMPT_COMMAND[*]:-};" != *";__zotcli_hook;"* ]]; then
            PROMPT_COMMAND="__zotcli_hook;${PROMPT_COMMAND:-}"
        fi
    fi

    return $exitcode
}

zot() { zotcli "$@"; }

__zotcli_hook() {
    local prev=$?
    if [[ "${ZOTCLI_VISUAL:-}" == "1" ]]; then
        local path="${ZOTCLI_PATH:-^}"
        local sync="${ZOTCLI_SYNC_AGE:-}"
        local info="\033[2m(zot)\033[0m $path"
        [[ -n "$sync" ]] && info+="  \033[2m[synced $sync]\033[0m"
        echo -e "$info" >&2
    fi
    return $prev
}
```

---

## 14. Completions

In `completions/bash/zotcli.bash`, after the wrapper and hook definitions.

### Subcommand completion

```
zotcli <TAB> → cd pwd ls tree cat get find sync connect config py off
```

### Path completion (cd, ls)

- Read collection names from `data/cache.json` (fast, no API call).
- For `^/` prefix: resolve segments, complete at resolved level.
- For relative paths: complete at current level (from state).
- Append `/` to collection names.
- `compopt -o nospace` to allow continuing after `/`.

### Item completion (cat, get)

No dynamic completion in v3 (would require API calls, too slow).
Complete only flags.

### Flag completion

- `ls`: `--sort`, `--reverse`, `--unfiled`
- `get`: `--bibtex`, `--json`, `--bib`, `--style`, `-o`
- `find`: `--field`, `--scope`, `--tag`, `--type`
- `tree`: `--depth`
- Global: `--fresh`

### Register for both names

```bash
complete -F _zotcli zotcli
complete -F _zotcli zot
```

---

## 15. Ordering & Sorting

`ls` output:

1. **Collections first**, alphabetical (numeric prefixes sort naturally).
2. **Items second**, sorted by `ls.default_sort` config:
   - `name`: citation key or title, alphabetical.
   - `date`: `data.date`, newest first.
   - `type`: `data.itemType`, alphabetical.
   - `creator`: first creator last name, alphabetical.
3. `--sort` overrides config. `--reverse` inverts.
4. Children (inside item): sorted by filename/title alphabetically.

---

## 16. Multi-collection Items

When `len(data.collections) > 1` and the current collection is NOT
`data.collections[0]`, display with `→` prefix:

```
→ jurafsky2026    Book    Jurafsky, Martin (2026)
```

Display-only. Does not affect any operations.

---

## 17. Unfiled Items

Items with `data.collections == []`:
- `zotcli ls --unfiled` at root lists them.
- Not shown in default `ls` at root.
- `zotcli find --scope library` can find them.

---

## 18. Error Handling

Errors to stderr. Exit 1 for user errors, exit 2 for system/API errors.

Format: `error: <message>` (red when TTY).

Examples:
- `cat unknown` → `error: 'unknown' not found. Use 'find' to search.`
- `cd nonexistent` → `error: Collection 'nonexistent' not found. Available: A, B, C`
- No credentials → `error: Credentials not found. Run 'zotcli connect'.`

---

## 19. Tests

`tests/smoke.py`:

1. All modules import.
2. `state.py`: round-trip with item_key fields.
3. `navigator.py`: `^`, `..`, `-`, absolute, relative, item entry, item exit.
4. `config.py`: load defaults, overlay, dot-notation get/set.
5. `formatters.py`: colors, citation key extraction, multi-collection indicator.
6. `cache.py`: `sync_age_human()`.
7. `finder.py`: local filter patterns.

All tests use temp files. Never pollute `data/` or `config/`.

---

## 20. .gitignore

```
spells/zotcli/config/credentials.env
spells/zotcli/config/zotcli.yaml
spells/zotcli/data/state.json
spells/zotcli/data/cache.json
spells/zotcli/.venv/
```

---

## 21. README.md

Rewrite for v3. Include: overview, setup, quick start examples,
full command reference, configuration, visual mode, Python REPL,
alias (`zot`).

---

## 22. Implementation Notes for Claude Code

### Priority order

1. `config.py` + `config/zotcli.defaults.yaml`
2. `state.py` (updated with item_key)
3. `navigator.py` (updated with item nav + `^`)
4. `cache.py` (add sync_age_human)
5. `formatters.py` (update root symbol, multi-collection, sorting)
6. `finder.py` (new)
7. `commands.py` (all handlers + env export protocol)
8. `shell_py.py` (REPL with configurable imports)
9. `bin/zotcli` (bash entrypoint)
10. `completions/bash/zotcli.bash` (wrapper + completions + hook)
11. `tests/smoke.py`
12. `pyproject.toml`, `Makefile`, `.gitignore`, `README.md`

### Key differences from v2

- Root: `^` not `~`. Update ALL code, tests, output, state, completions.
- `cat` strict match only. Remove substring cascade.
- `cd` enters items. State tracks `item_key` and `item_label`.
- New: `find`, `config`, `off` commands.
- Visual mode via PROMPT_COMMAND, auto-activated by wrapper.
- Wrapper function in `completions/bash/zotcli.bash`, not in `bin/zotcli`.
- Env var export protocol (`__ZOTCLI_ENV__` lines).
- venv via `uv` + `pyproject.toml`.
- `pyyaml` as new dependency.

### Preserve from v2

- `client.py` logic.
- Atomic state writes.
- Color constants pattern.
- Collection tree traversal (extend, don't rewrite).
- `connect` command flow.
- `get` attachment download logic.

### Do NOT

- Use `ruamel.yaml`. `pyyaml` is sufficient.
- Cache items globally. Per-collection fetch only.
- Add IPython/ptpython as deps. Use stdlib `code.interact()`.
- Use `python-dotenv`. Parse credentials manually.
- Shadow the `pyzotero` package name.
- Modify files outside the spell directory.
