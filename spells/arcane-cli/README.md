# arcane-cli

Operational CLI for Arcane compose projects.

## Usage

```bash
arcane <subcommand> [projects...] [--exclude|-e excludes...] [--device|-d device]
arcane exec [--device|-d device] <project> <service> -- <command...>
arcane bash [--device|-d device] [--project|-p project] <service>
arcane rm <containers|images|networks|volumes|all> [projects...] [--exclude|-e excludes...] [--device|-d device]
```

## Subcommands

| Command | Description |
|---|---|
| `up`, `down`, `pull`, `restart`, `status` | Batch lifecycle commands for selected projects |
| `cd` | Shell helper when `init/env.bash` is sourced |
| `path` | Print the absolute path for one project |
| `exec` | Run a command inside one project service |
| `bash` | Open `bash` in one service, inferring the project when the service name is unique |
| `resources` | Show containers, images, networks, and volumes tied to projects |
| `rm` | Remove one resource type for selected projects |
| `clean`, `purge` | Legacy cleanup shortcuts |
| `favorites` | Generate portable bookmarks HTML |
| `dump`, `restore` | Backup and restore `.env` files |

## Examples

```bash
arcane up
arcane up -d lilith kopia taildns
arcane exec -d lilith taildns app -- sh -lc 'echo ok'
arcane bash -d lilith vibecode
arcane bash -d lilith -p vibespace vibecode
arcane resources -d lilith taildns
arcane rm images -d lilith taildns
arcane path -d lilith taildns
cd "$(arcane path -d lilith taildns)"
```

## Notes

- `run` was removed. Use `exec` for service-level commands and lifecycle subcommands for project-wide actions.
- `exec` keeps `--` mandatory so the command boundary stays explicit.
- `arcane cd <project>` changes the current shell directory only when the Sigils init script has been sourced.
- `ARCANE_DIR` defaults to `~/arcane`.
