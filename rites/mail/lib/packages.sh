#!/usr/bin/env bash

mail_required_packages() {
    printf '%s\n' isync aerc notmuch pass gnupg2 msmtp
}

mail_missing_packages() {
    local pkg

    for pkg in $(mail_required_packages); do
        dpkg -s "$pkg" >/dev/null 2>&1 || printf '%s\n' "$pkg"
    done
}

mail_install_packages() {
    local missing_packages=()
    local pkg
    local prefix=()

    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        missing_packages+=("$pkg")
    done < <(mail_missing_packages)

    [[ ${#missing_packages[@]} -gt 0 ]] || return 0

    if [[ "$(id -u)" -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            prefix=(sudo)
        else
            echo "error: missing packages detected and sudo is unavailable" >&2
            return 1
        fi
    fi

    mail_exec_or_print "${prefix[@]}" apt-get update
    mail_exec_or_print "${prefix[@]}" apt-get install -y "${missing_packages[@]}"
}
