# totp

Terminal TOTP code generator for two-factor authentication.
Generate RFC 6238 time-based one-time passwords from the command line.

## Install

```
make -C spells/totp install
```

Detects the distro automatically and installs `oathtool` + `xclip`.

### Dependencies

- `oathtool` (oath-toolkit) — TOTP code generation
- `xclip` | `wl-copy` | `xsel` — clipboard support (optional, for `--clip`)

## Usage

```
totp add --name github --secret JBSWY3DPEHPK3PXP
totp add --name github --clip                        # read secret from clipboard
totp add --uri "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
totp list
totp get
totp get --name github
totp get --name github --clip                        # copy code to clipboard
totp export --name github
totp remove --name github
```

## Storage

Secrets are stored in `spells/totp/data/keys` (inside the repository).
The `data/` directory is already excluded by `.gitignore` — secrets are never committed.

The file uses a simple tab-separated format: `name\tsecret\talgorithm\tdigits\tperiod`.

## Security

- Keys file: permissions `600` (owner read/write only)
- Data directory: permissions `700` (owner access only)
- Permissions are checked and auto-corrected on every invocation
- Secrets are never committed to git (`spells/*/data/*` is in `.gitignore`)
