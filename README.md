# Sigils

Feature-oriented shell tooling workspace.

## Repository Layout

```text
.
├── bin/                       # symlinks only -> spells/*/bin/*
├── spells/
│   ├── <spell>/
│   │   ├── bin/               # user-facing entrypoints for the spell
│   │   ├── lib/               # spell-local libraries
│   │   ├── tests/             # spell-local tests/fixtures
│   │   ├── config/            # spell-local config files
│   │   ├── services/
│   │   │   └── systemd/
│   │   │       ├── user/
│   │   │       └── system/
│   │   ├── completions/
│   │   │   ├── bash/
│   │   │   ├── zsh/
│   │   │   └── fish/
│   │   ├── desktop/           # placeholder
│   │   ├── data/.gitkeep
│   │   ├── logs/.gitkeep
│   │   ├── Makefile
│   │   └── README.md
├── init/
│   └── env.bash
├── lib/
│   └── common/                # shared-code convention (reserved)
└── docs/
```

## Environment bootstrap

Source `init/env.bash` from your shell startup file. It:

- prepends root `bin/` to `PATH`
- loads bash completions from `spells/*/completions/bash/*.bash`

## Make targets

- `make link`: create/update symlinks in root `bin/`
- `make unlink`: remove only symlinks from root `bin/`
- `make list`: list spells and detected entrypoints
- `make executable`: ensure `spells/*/bin/*` are executable
- `make new SPELL=<name>`: generate a full spell scaffold and run `make link`
- `make test`, `make check`, `make fmt`, `make clean`: delegate to spell Makefiles when available

## Examples

- `arcane status`
- `mdview README.md`
