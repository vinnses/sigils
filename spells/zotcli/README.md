# zotcli

Filesystem-like CLI for navigating and querying a Zotero library via [pyzotero](https://github.com/urschrei/pyzotero). Works with the Zotero web API — no Zotero Desktop required.

## Setup

```sh
make install          # install dependencies via uv
zotcli connect        # enter library ID + API key
```

Get your credentials at <https://www.zotero.org/settings/keys>.

## Quick Start

```sh
zotcli ls                      # list root collections
zotcli cd ^/1.Books            # enter a collection
zotcli ls                      # list its contents
zotcli cat jurafsky2026        # show item metadata
zotcli get jurafsky2026 --bibtex  # export BibTeX
zotcli cd jurafsky2026         # enter item, see attachments
zotcli ls                      # list attachments/notes
zotcli get jurafsky2026:0-FullBook  # download attachment
zotcli --help                 # top-level help
```

## Root Symbol

**`^`** represents the Zotero library root (like `~` for home, but safe in bash).

```
^                     root
^/1.Books             absolute path
^/1.Books/AI          nested
1.Books               relative from current location
..                    parent
-                     previous location
```

## Commands

### Navigation

| Command | Description |
|---|---|
| `zotcli cd [path]` | Navigate. Supports `^`, `^/path`, `..`, `-`, relative. No args = root. |
| `zotcli pwd` | Print current path. |
| `zotcli tree [--depth N]` | Recursive tree. Default: unlimited depth. |

### Listing

| Command | Description |
|---|---|
| `zotcli ls` | List current level (collections + items, or children if inside item). |
| `zotcli ls <path>` | List a collection or item without entering it. |
| `zotcli ls --sort <field>` | Sort by: `name` (default), `date`, `type`, `creator`. |
| `zotcli ls --reverse` | Reverse sort order. |
| `zotcli ls --unfiled` | At root: list items not in any collection. |
| `zotcli ls --fields <csv>` | Choose output columns: `label,title,citation_key,author,year,type,meta,key`. |

### Reading

| Command | Description |
|---|---|
| `zotcli cat <ref>` | Show metadata for an item or child (exact match only). |
| `zotcli cat <item>:<child>` | Show child metadata without cd-ing into the item. |

### Searching

| Command | Description |
|---|---|
| `zotcli find <pattern>` | Search in current collection (title, creators, citation key). |
| `zotcli find <pattern> --field <f>` | Search a specific field: `title`, `creator`, `tag`, `doi`, `year`, `key`, `type`. |
| `zotcli find <pattern> --scope library` | Search entire library (server-side). |
| `zotcli find --tag <tag>` | Filter by tag. Multiple `--tag` flags = AND. |
| `zotcli find --type <itemType>` | Filter by item type (`book`, `journalArticle`, etc). |
| `zotcli find --fields <csv>` | Choose output columns (same aliases as `ls --fields`). |

### Exporting

| Command | Description |
|---|---|
| `zotcli get <item>` | Export in default format (configurable, default: `bibtex`). |
| `zotcli get <item> --bibtex` | Export BibTeX to stdout. |
| `zotcli get <item> --json` | Export JSON to stdout. |
| `zotcli get <item> --bib [--style <csl>]` | Formatted bibliography (default style: apa). |
| `zotcli get <item>:<child>` | Download attachment to current directory. |
| `zotcli get <item>:<child> -o <path>` | Download to specified path. |

### Setup & Maintenance

| Command | Description |
|---|---|
| `zotcli connect` | Interactive credential setup. |
| `zotcli sync` | Force-refresh cache from API. |
| `zotcli off` | Deactivate visual mode + reset navigation to root. |
| `zotcli config` | Print effective configuration. |
| `zotcli config <key> <value>` | Set a configuration value (dot-notation). |

### Python REPL

| Command | Description |
|---|---|
| `zotcli py` | Interactive Python REPL with auto-imports. |
| `zotcli py -c "<code>"` | Execute inline code. |
| `zotcli py <script.py>` | Execute a script file. |

Auto-imports are configured in `config/imports.py`.

### Global Flags

| Flag | Description |
|---|---|
| `--fresh` | Bypass cache for this invocation, fetch directly from API. |

## Visual Mode (PS1 Integration)

When the spell is enabled and the Sigils shell init is sourced, `zotcli` installs:

- a shell wrapper that captures `__ZOTCLI_ENV__` exports
- `__zotcli_ps1` for prompt-aware integrations
- a prompt hook that shows the current Zotero path when visual mode is active

Visual mode activates automatically on the first `zotcli` command in a shell session. The canonical prompt path uses `^`, for example: `^/1.Books [5m ago]`.

`zotcli off` clears the prompt state and resets navigation to root.

If the spell is enabled but your shell has not loaded it yet, source the Sigils init:

```sh
source /path/to/sigils/init/env.bash
```

## Configuration

```sh
zotcli config                          # show effective config
zotcli config ls.default_sort date     # sort by date by default
zotcli config get.default_format json  # default export format
```

Config keys:

| Key | Default | Description |
|---|---|---|
| `ls.default_sort` | `name` | Default sort: `name`, `date`, `type`, `creator` |
| `ls.sort_reverse` | `false` | Reverse sort order |
| `get.default_format` | `bibtex` | Default export: `bibtex`, `json`, `bib` |
| `get.bib_style` | `apa` | CSL style for `--bib` |
| `cache.ttl_seconds` | `3600` | Cache TTL (1 hour) |
| `visual.auto` | `true` | Auto-activate the prompt hook on first use |
| `visual.color` | `cyan` | PS1 color: `cyan`, `green`, `yellow`, `red`, `blue`, `magenta`, `white`, `bright_*` |
| `visual.show_sync_age` | `true` | Show sync age footer in listing commands |

Env vars override config: `ZOTCLI_LS__DEFAULT_SORT=date` (prefix + double underscore).

## Alias

`zot` is a short alias for `zotcli`:

```sh
zot cd ^/1.Books
zot ls --sort date
```

## Navigation Model

```
^ (root)
├── Collection/
│   ├── Subcollection/
│   │   ├── item          ← cd into with: zotcli cd jurafsky2026
│   │   │   ├── attachment (child)
│   │   │   └── note (child)
│   │   └── item
│   └── item
└── Collection/
    └── ...
```

Items are resolved by: citation key → item key → exact title.
Children are resolved by: exact filename → exact title → child key.

The `:` shortcut allows accessing children without `cd`:

```sh
zotcli cat jurafsky2026:0-FullBook    # show child metadata
zotcli get jurafsky2026:0-FullBook    # download attachment
```
