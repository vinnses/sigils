# sigils

Minimal spell manager for the Sigils workspace.

## Commands

```bash
sigils list
sigils link
sigils unlink
sigils executable
sigils enable <spell>
sigils disable <spell>
sigils new <spell>
sigils install [--dev] [--all|<spell>]
sigils test [--all|<spell>]
sigils check [--all|<spell>]
sigils fmt [--all|<spell>]
sigils clean [--all|<spell>]
sigils man <spell>
sigils cd <spell>
sigils rites
sigils rites list
sigils rites path <rite>
sigils rites status [--all|<rite>]
sigils rites doctor [--all|<rite>]
sigils rite <rite> [args...]
```

`config/spells.disabled` is the source of truth for spells that should not be linked into `bin/` and should not have shell init or completions sourced.

`sigils install` and the other maintenance commands delegate to the workspace `Makefile`, so `sigils install mdview` is the short form of `make -C <sigils-root> install SPELL=mdview`.
