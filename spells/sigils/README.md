# sigils

Minimal spell manager for the Sigils workspace.

## Commands

```bash
sigils list
sigils enable <spell>
sigils disable <spell>
sigils new <spell>
```

`config/spells.disabled` is the source of truth for spells that should not be linked into `bin/` and should not have shell init or completions sourced.
