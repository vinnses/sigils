# arcane-cli

Operational CLI for Arcane compose projects.

## Usage

```bash
arcane <subcommand> [projects...] [--exclude|-e excludes...] [--device|-d device]
arcane exec [--device|-d device] [--project|-p project] <service> -- <command...>
arcane list [--device|-d device] [project [containers|images|networks|volumes|all]]
arcane remove [--device|-d device] [--force|-f] <project> <containers|images|networks|volumes|all>[,<type>...] [names...]
```

## Subcommands

| Command | Description |
|---|---|
| `up`, `down`, `pull`, `restart` | Batch lifecycle commands for selected projects |
| `ps` | Show compose service status for selected projects |
| `list` | List projects, or list containers/images/networks/volumes for one project |
| `exec` | Run a command inside one service, inferring the project when the service name is unique |
| `remove`, `rm` | Remove project containers, images, networks, volumes, or all resources |
| `archive`, `unarchive` | Move projects between a device and `archived/<device>/` |
| `clone` | Copy one project from a device to another, optionally with a new name |
| `clean` | Stop services and remove images for selected projects |
| `purge` | Stop services and remove images and volumes for selected projects |
| `nginx-urls` | Generate portable bookmarks HTML from nginx URLs |
| `dump`, `restore` | Backup and restore environment files, optionally including Docker volumes |

## Examples

```bash
arcane up
arcane up -d lilith kopia taildns
arcane list -d lilith
arcane list -d lilith --archived
arcane list -d lilith taildns
arcane list -d lilith taildns containers
arcane ps -d lilith taildns
arcane exec -d lilith app -- sh -lc 'echo ok'
arcane exec -d lilith -p taildns app -- sh -lc 'echo ok'
arcane exec -d lilith -p vibespace vibecode -- bash
arcane remove -d lilith taildns images
arcane remove -d lilith --force taildns containers taildns-app-1
arcane rm -d lilith taildns images,volumes
arcane archive -d lilith old-project
arcane unarchive -d lilith old-project
arcane clone --from lilith --to asmodeus taildns --new taildns-copy
arcane dump --only-env -d lilith taildns --output ~/taildns-env.7z
arcane dump --volumes -d lilith taildns --output ~/taildns-full.7z
arcane restore ~/taildns-full.7z --force
arcane nginx-urls -d lilith
```

## Notes

- `run` was removed. Use `exec` for service-level commands and lifecycle subcommands for project-wide actions.
- `exec` keeps `--` mandatory so the command boundary stays explicit.
- `exec` uses `--project/-p` when a service name exists in multiple projects.
- `dump --only-env` includes conventional `.env` files plus files referenced by Compose `env_file:`.
- `dump --volumes` writes a manifest plus `files/` and `volumes/` payloads. Restore refuses existing volumes unless `--force` is used.
- `ARCANE_DIR` defaults to `~/arcane`.
