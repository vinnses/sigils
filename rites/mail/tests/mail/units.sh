#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RITE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

run_mail() {
    HOME="$TMP_HOME" SIGILS_MAIL_DRY_RUN=1 "$RITE_DIR/bin/mail" "$@"
}

OUTPUT="$(run_mail status)"
grep -Fq "gpg: missing" <<<"$OUTPUT"
grep -Fq "pass: missing" <<<"$OUTPUT"

ACCOUNT_FILE="$TMP_HOME/accounts.env"
cat >"$ACCOUNT_FILE" <<'EOF'
MAIL_ACCOUNTS="personal"
MAIL_PERSONAL_ADDRESS="me@example.com"
MAIL_PERSONAL_NAME="Me Example"
MAIL_PERSONAL_IMAP_HOST="imap.example.com"
MAIL_PERSONAL_IMAP_PORT="993"
MAIL_PERSONAL_SMTP_HOST="smtp.example.com"
MAIL_PERSONAL_SMTP_PORT="587"
EOF

HOME="$TMP_HOME" SIGILS_MAIL_ACCOUNT_FILE="$ACCOUNT_FILE" SIGILS_MAIL_DRY_RUN=1 \
    "$RITE_DIR/bin/mail" setup

test -f "$TMP_HOME/.mbsyncrc"
test -f "$TMP_HOME/.config/aerc/accounts.conf"
test -f "$TMP_HOME/.msmtprc"
test -f "$TMP_HOME/.notmuch-config"

grep -Fq "imap.example.com" "$TMP_HOME/.mbsyncrc"
grep -Fq "smtp.example.com" "$TMP_HOME/.msmtprc"
grep -Fq "me@example.com" "$TMP_HOME/.config/aerc/accounts.conf"

SYNC_OUTPUT="$(run_mail sync)"
grep -Fq "dry-run: mbsync -a" <<<"$SYNC_OUTPUT"

INDEX_OUTPUT="$(run_mail index)"
grep -Fq "dry-run: notmuch new" <<<"$INDEX_OUTPUT"
