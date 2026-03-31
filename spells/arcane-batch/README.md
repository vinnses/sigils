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
| `purge`   | Clean + remove volumes                   |
| `status`  | Show service status                      |
| `ls`      | List projects on device (all/up/down)    |
| `cd`      | Print absolute path for one project      |
| `run`     | Run arbitrary command in each project    |
| `exec`    | Alias for `run`                          |
| `favorites` | Generate portable bookmarks HTML (nginx URLs grouped by device/project) |
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
arcane ls                           # list projects with up/down status
arcane ls --up                      # list only running projects
arcane ls --down -d lilith          # list only stopped projects on lilith
cd "$(arcane cd taildns)"           # jump to a project directory
arcane run -- docker compose config # run command in each project
arcane exec taildns -- docker compose logs -n 50
arcane favorites                    # one portable HTML for browser import
arcane favorites -o ~/Bookmarks/arcane.html
arcane favorites -d lilith          # only one device
arcane dump                         # backup all .env files
arcane restore backup.7z            # restore .env files
```

## Environment

- `ARCANE_DIR` — path to arcane repository (default: `~/arcane`)

## Dependencies

- `docker` with compose plugin
- `7z` (`p7zip-full`) — only for dump/restore
