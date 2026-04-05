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
- loads bash init/completion files only for enabled spells

Enabled and disabled spells are controlled by `config/spells.disabled`.
Use `sigils list`, `sigils enable <spell>`, and `sigils disable <spell>` to manage that state.

## Make targets

- `make link`: recreate symlinks in root `bin/` for enabled spells only
- `make unlink`: remove only symlinks from root `bin/`
- `make list`: list spells, status, and detected entrypoints
- `make executable`: ensure `spells/*/bin/*` are executable
- `make new SPELL=<name>`: generate a full spell scaffold and run `make link`
- `make test`, `make check`, `make fmt`, `make clean`: delegate to spell Makefiles when available
