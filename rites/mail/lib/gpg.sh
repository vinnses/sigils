#!/usr/bin/env bash

mail_default_gpg_key() {
    command -v gpg >/dev/null 2>&1 || return 1
    gpg --list-secret-keys --with-colons 2>/dev/null | awk -F: '/^sec:/ {print $5; exit}'
}

mail_gpg_name() {
    if [[ -n "${MAIL_GPG_NAME:-}" ]]; then
        printf '%s\n' "$MAIL_GPG_NAME"
        return 0
    fi

    git config --global user.name 2>/dev/null || true
}

mail_gpg_email() {
    if [[ -n "${MAIL_GPG_EMAIL:-}" ]]; then
        printf '%s\n' "$MAIL_GPG_EMAIL"
        return 0
    fi

    git config --global user.email 2>/dev/null || true
}

mail_ensure_gpg_key() {
    local key_id
    local name
    local email
    local uid

    key_id="$(mail_default_gpg_key || true)"
    [[ -n "$key_id" ]] && return 0

    name="$(mail_gpg_name)"
    email="$(mail_gpg_email)"

    if [[ -z "$name" || -z "$email" ]]; then
        if [[ "${SIGILS_MAIL_DRY_RUN:-0}" == "1" ]]; then
            printf 'dry-run: gpg --batch --passphrase %q --quick-generate-key %q default default 1y\n' '' 'MAIL_GPG_NAME <MAIL_GPG_EMAIL>'
            return 0
        fi
        echo "error: no GPG secret key found and MAIL_GPG_NAME / MAIL_GPG_EMAIL are not set" >&2
        return 1
    fi

    uid="$name <$email>"
    mail_exec_or_print gpg --batch --passphrase '' --quick-generate-key "$uid" default default 1y
}
