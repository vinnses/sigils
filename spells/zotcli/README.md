# zotcli

Zotero CLI interface via [pyzotero](https://github.com/urschrei/pyzotero).

## Setup

```sh
make install          # install pyzotero
zotcli connect        # enter library ID + API key
```

Get your credentials at <https://www.zotero.org/settings/keys>.

## Usage

```
zotcli [--fresh] <subcommand> [args]
```

| Subcommand | Description |
|---|---|
| `collections [--flat]` | List collections as a tree (or flat with `--flat`) |
| `items <collection>` | List items in a collection (name or key) |
| `info <item>` | Print full metadata for an item (key or title substring) |
| `attachments <item>` | List attachments for an item |
| `connect` | Interactive credential setup |
| `sync` | Force-refresh the local cache from the API |

**Global flag:** `--fresh` — bypass cache and fetch directly from the API.

Run `zotcli` with no arguments for an interactive Python shell.

## Cache

Read subcommands (`collections`, `items`, `info`, `attachments`) use a local
cache at `data/cache.json` to avoid repeated API calls. The cache is refreshed
automatically when older than 1 hour. Run `zotcli sync` to refresh immediately.
