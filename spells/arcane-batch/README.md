# arcane-batch

Batch Docker Compose operations across the [arcane](https://github.com/vinnses/arcane) repository.

## Usage

```bash
arcane <subcommand> [projects...] [--exclude|-e excludes...] [--device|-d device]
```

## Subcommands

| Command   | Description                              |
|-----------|------------------------------------------|
| `up`      | Start services (`docker compose up -d`)  |
| `down`    | Stop services (`docker compose down`)    |
| `pull`    | Pull images and restart                  |
| `restart` | Full restart (down + pull + up)           |
| `clean`   | Remove services and images               |
| `status`  | Show service status                      |
| `dump`    | Backup all .env files to encrypted 7z    |
| `restore` | Restore .env files from 7z archive       |

## Examples

```bash
arcane up                           # up all projects on $(hostname)
arcane up kopia taildns             # up only kopia and taildns
arcane down --exclude asmodeus      # down all except arcane UI
arcane restart taildns              # restart only taildns
arcane up -d lilith                 # up all projects on lilith
arcane status                       # ps for all projects
arcane dump                         # backup all .env files
arcane restore backup.7z            # restore .env files
```

## Environment

- `ARCANE_DIR` — path to arcane repository (default: `~/arcane`)

## Dependencies

- `docker` with compose plugin
- `7z` (`p7zip-full`) — only for dump/restore
