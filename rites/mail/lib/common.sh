#!/usr/bin/env bash

MAIL_LOG_FILE="${MAIL_LOG_FILE:-$RITE_DIR/logs/mail.log}"

mail_exec_or_print() {
    if [[ "${SIGILS_MAIL_DRY_RUN:-0}" == "1" ]]; then
        printf 'dry-run:'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

mail_print_status() {
    local gpg_key
    local missing_packages

    gpg_key="$(mail_default_gpg_key || true)"
    if [[ -n "$gpg_key" ]]; then
        printf 'gpg: configured (%s)\n' "$gpg_key"
    else
        printf 'gpg: missing\n'
    fi

    if mail_pass_is_initialized; then
        printf 'pass: configured\n'
    else
        printf 'pass: missing\n'
    fi

    missing_packages="$(mail_missing_packages)"
    if [[ -n "$missing_packages" ]]; then
        printf 'packages: missing'
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] || continue
            printf ' %s' "$pkg"
        done <<<"$missing_packages"
        printf '\n'
    else
        printf 'packages: ready\n'
    fi
}

mail_run_doctor() {
    local status=0

    mail_print_status

    command -v mbsync >/dev/null 2>&1 || status=1
    command -v notmuch >/dev/null 2>&1 || status=1
    command -v pass >/dev/null 2>&1 || status=1
    [[ -f "$HOME/.mbsyncrc" ]] || status=1
    [[ -f "$(mail_config_home)/aerc/accounts.conf" ]] || status=1
    [[ -f "$HOME/.msmtprc" ]] || status=1
    [[ -f "$HOME/.notmuch-config" ]] || status=1

    return "$status"
}

mail_run_setup() {
    mail_install_packages
    mail_ensure_gpg_key

    if ! mail_pass_is_initialized; then
        local key_id

        key_id="$(mail_default_gpg_key || true)"
        [[ -n "$key_id" ]] || [[ "${SIGILS_MAIL_DRY_RUN:-0}" == "1" ]] || {
            echo "error: unable to initialize pass without a GPG key" >&2
            return 1
        }
        if [[ -n "$key_id" ]]; then
            mail_exec_or_print pass init "$key_id"
        else
            printf 'dry-run: pass init %s\n' 'MAIL_GPG_KEY'
        fi
    fi

    mail_load_accounts
    mail_validate_accounts
    mail_generate_configs
}

mail_run_uninstall() {
    local targets=(
        "$HOME/.mbsyncrc"
        "$(mail_config_home)/aerc/accounts.conf"
        "$HOME/.msmtprc"
        "$HOME/.notmuch-config"
    )
    local target

    if [[ "${SIGILS_MAIL_FORCE:-0}" != "1" && "${SIGILS_MAIL_DRY_RUN:-0}" != "1" ]]; then
        printf 'Remove generated mail configuration files? [y/N] ' >&2
        read -r answer
        [[ "$answer" == "y" || "$answer" == "Y" ]] || return 1
    fi

    for target in "${targets[@]}"; do
        if [[ "${SIGILS_MAIL_DRY_RUN:-0}" == "1" ]]; then
            printf 'dry-run: rm -f %s\n' "$target"
        else
            rm -f "$target"
        fi
    done
}

mail_run_test() {
    mail_print_status
    mail_exec_or_print mbsync -a
    mail_exec_or_print notmuch new
}
