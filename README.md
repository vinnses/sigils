# Sigils

Feature-oriented shell tooling workspace.

- `spells/` are user-facing tools linked into root `bin/`
- `rites/` are internal setup and maintenance workflows reached via `sigils`

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
├── rites/
│   ├── <rite>/
│   │   ├── bin/               # internal rite entrypoint, reached via sigils
│   │   ├── lib/               # rite-local libraries
│   │   ├── tests/             # rite-local tests/fixtures
│   │   ├── docs/              # rite-local docs
│   │   ├── config/            # rite-local config files
│   │   ├── templates/         # rite-local config templates
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
- `sigils rites`: list internal rites
- `sigils rites status [--all|<rite>]`: aggregate rite status
- `sigils rites doctor [--all|<rite>]`: aggregate rite diagnostics
- `sigils rite <name> [args...]`: dispatch to a rite entrypoint
- `make executable`: ensure `spells/*/bin/*` are executable
- `make new SPELL=<name>`: generate a full spell scaffold and run `make link`
- `make test`, `make check`, `make fmt`, `make clean`: delegate to spell Makefiles when available

## Examples

- `arcane status`
- `mdview README.md`
