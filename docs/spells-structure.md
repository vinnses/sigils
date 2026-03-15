# Spells layout (by-feature)

Top-level conventions:

- `spells/<spell>/bin/` entrypoints for a spell.
- `spells/<spell>/lib/` spell-scoped libraries.
- `spells/<spell>/tests/` spell-scoped tests and fixtures.
- `spells/<spell>/config/` spell configuration files.
- `spells/<spell>/services/systemd/{user,system}/` service units per environment.
- `spells/<spell>/completions/{bash,zsh,fish}/` completion files.
- `spells/<spell>/desktop/` desktop placeholders.
- `spells/<spell>/{data,logs}/` runtime directories with `.gitkeep`.

Cross-cutting conventions:

- Root `bin/` contains only symlinks to `spells/*/bin/*`.
- Root `lib/common/` is reserved for future shared code.
- `init/env.bash` prepends root `bin/` and loads bash completions via `spells/*/completions/bash/*.bash`.
