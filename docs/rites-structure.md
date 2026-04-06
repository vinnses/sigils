# Rites Layout

Top-level conventions:

- `rites/<rite>/bin/<rite>` is the single entrypoint for a rite.
- `rites/<rite>/lib/` holds rite-scoped libraries.
- `rites/<rite>/tests/` holds rite-scoped tests and fixtures.
- `rites/<rite>/docs/` holds rite-local documentation.
- `rites/<rite>/config/` holds example configuration and non-secret defaults.
- `rites/<rite>/templates/` holds config templates rendered during setup.
- `rites/<rite>/{data,logs}/` are runtime directories and must keep `.gitkeep`.

Common rite contract:

- `setup`
- `status`
- `doctor`
- `docs`
- `uninstall`

Optional subcommands are rite-specific.

Important differences from spells:

- rites are not linked into root `bin/`
- rites are not enable/disable managed through `config/spells.disabled`
- rites are reached through `sigils rites ...` and `sigils rite <name> ...`
