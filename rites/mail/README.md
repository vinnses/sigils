# mail

Bootstrap and maintain a local CLI mail stack through Sigils rites.

## Commands

```bash
sigils rite mail setup
sigils rite mail status
sigils rite mail doctor
sigils rite mail docs
sigils rite mail uninstall
sigils rite mail sync
sigils rite mail index
sigils rite mail send-test
sigils rite mail test
```

This rite is intentionally internal to Sigils. It is not linked into root `bin/`.

## Accounts File

The rite expects an accounts file, by default at:

```bash
$HOME/.config/sigils/mail/accounts.env
```

Example:

```bash
MAIL_ACCOUNTS="personal work"

MAIL_PERSONAL_NAME="Me Example"
MAIL_PERSONAL_ADDRESS="me@example.com"
MAIL_PERSONAL_IMAP_HOST="imap.example.com"
MAIL_PERSONAL_SMTP_HOST="smtp.example.com"

MAIL_WORK_NAME="Me at Work"
MAIL_WORK_ADDRESS="me@company.com"
MAIL_WORK_IMAP_HOST="imap.company.com"
MAIL_WORK_SMTP_HOST="smtp.company.com"
```

Passwords are not stored in the accounts file. The generated configs expect:

```bash
pass show mail/personal/imap
pass show mail/personal/smtp
```

## Verification

- `sigils rites`
- `sigils rite mail status`
- `sigils rite mail doctor`
- `sigils rite mail setup`
- `sigils rite mail sync`
- `sigils rite mail index`
