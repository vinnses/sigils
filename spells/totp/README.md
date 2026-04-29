# totp

Terminal TOTP code generator for two-factor authentication.
Generate RFC 6238 time-based one-time passwords from the command line.

## Install

```
make -C spells/totp install
```

Detects the distro automatically and installs the basic TOTP and clipboard tools.

### Dependencies

| Tool | Purpose | Required |
|------|---------|----------|
| `oathtool` (oath-toolkit) | TOTP code generation | yes |
| `gpg` (gnupg) | Recommended encrypted storage via `gpg-agent` | yes |
| `openssl` | Legacy passphrase/keyring encrypted storage | optional |
| `secret-tool` (libsecret-tools) | GNOME Keyring backend | optional legacy |
| `xclip` \| `wl-copy` \| `xsel` | Clipboard support (`--xclip`) | optional |

## First-time setup

Run `totp init` before adding any accounts. The default backend is `gpg`, which
uses `gpg-agent` for prompting and cache TTLs without depending on GNOME.

```
totp init --backend gpg
```

## Usage

```
totp add github --secret JBSWY3DPEHPK3PXP
totp add github --xclip                              # read secret from clipboard
totp add --uri "otpauth://totp/GitHub:user?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
totp ls
totp get github
totp github
totp copy github
totp get github --xclip                              # print and copy code
totp get --all                                       # reveal all current codes
totp export github
totp rm github
```

## Security

### Encryption at rest

The recommended backend encrypts secrets with `gpg --symmetric` and stores the
ciphertext in `spells/totp/data/keys.gpg`. `gpg-agent` handles prompting and
cache TTLs, so this works across desktop environments, window managers, TTYs,
and SSH sessions when GPG is configured.

The legacy `passphrase` and `keyring` backends use **AES-256-CBC + PBKDF2**
(600 000 iterations) via `openssl enc` and store ciphertext at
`spells/totp/data/keys.enc`.

### Passphrase Management

Recommended:

- `totp init --backend gpg`: uses `gpg-agent`; no GNOME Keyring dependency.

Compatibility:

- `totp init --backend passphrase`: prompts for the master passphrase.
- `totp init --backend keyring`: stores that passphrase with `secret-tool`.

### Re-keying

Run `totp init --backend <backend>` again at any time to migrate or re-key.
The current backend must decrypt existing accounts before the new backend is
written.

### Other protections

- `data/` directory: permissions `700` (owner access only)
- `data/keys.gpg` or `data/keys.enc`: permissions `600` (owner read/write only)
- Permissions auto-corrected on every invocation
- Secrets never committed to git (`spells/*/data/*` is in `.gitignore`)
- Passphrase variable overwritten with zeros before script exit (best-effort)

### Migration from unencrypted storage

If you used an older version of this spell, a plaintext `data/keys` file may
exist. Running `totp init` detects it, encrypts the accounts, and securely
overwrites and removes the plaintext file.
