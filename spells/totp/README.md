# totp

Terminal TOTP code generator for two-factor authentication.
Generate RFC 6238 time-based one-time passwords from the command line.

## Install

```
make -C spells/totp install
```

Detects the distro automatically and installs `oathtool`, `openssl`, and `xclip`.

### Dependencies

| Tool | Purpose | Required |
|------|---------|----------|
| `oathtool` (oath-toolkit) | TOTP code generation | yes |
| `openssl` | AES-256 encryption of secrets | yes |
| `secret-tool` (libsecret-tools) | GNOME Keyring integration | optional |
| `xclip` \| `wl-copy` \| `xsel` | Clipboard support (`--clip`) | optional |

## First-time setup

Run `totp init` before adding any accounts. This sets up the encrypted storage
and (if GNOME Keyring is available) stores the master passphrase in the keyring
so future invocations unlock automatically.

```
totp init
```

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

## Security

### Encryption at rest

Secrets are encrypted with **AES-256-CBC + PBKDF2** (600 000 iterations) via
`openssl enc`. The ciphertext is stored in `spells/totp/data/keys.enc`.
The plaintext never touches disk after initialization.

### Passphrase management — two tiers

1. **Graphical session (GNOME Keyring available):** The master passphrase is
   stored in GNOME Keyring via `secret-tool` and retrieved transparently on
   each invocation. No prompt required.

2. **TTY / headless session (no D-Bus or keyring):** The master passphrase is
   prompted interactively from the terminal (`TOTP passphrase:`). There is no
   silent fallback — the secrets are inaccessible without the passphrase.

Detection logic: `secret-tool` must be in PATH **and** either
`$DBUS_SESSION_BUS_ADDRESS` is set or `/run/user/$UID/bus` socket exists.

### Re-keying

Run `totp init` again at any time to change the master passphrase. The current
passphrase (from keyring or prompt) is required to decrypt existing accounts
before re-encrypting with the new one.

### Other protections

- `data/` directory: permissions `700` (owner access only)
- `data/keys.enc`: permissions `600` (owner read/write only)
- Permissions auto-corrected on every invocation
- Secrets never committed to git (`spells/*/data/*` is in `.gitignore`)
- Passphrase variable overwritten with zeros before script exit (best-effort)

### Migration from unencrypted storage

If you used an older version of this spell, a plaintext `data/keys` file may
exist. Running `totp init` detects it, encrypts the accounts, and securely
overwrites and removes the plaintext file.
