#!/bin/bash
# lib/sudoers.sh — sudoers drop-in generation and validation

SUDOERS_DROPIN="/etc/sudoers.d/99-pamusb"

sudoers_generate() {
    local username="$1"
    local luks_uuid="$2"
    local mapper_name="${3:-usb-secret}"
    local keyfile_path="${4:-/root/usb-luks.key}"
    local uid="$5"
    local template_dir="${SPELL_DIR}/templates"

    local content
    content=$(sed \
        -e "s|{{USERNAME}}|${username}|g" \
        -e "s|{{LUKS_UUID}}|${luks_uuid}|g" \
        -e "s|{{MAPPER_NAME}}|${mapper_name}|g" \
        -e "s|{{KEYFILE_PATH}}|${keyfile_path}|g" \
        -e "s|{{UID}}|${uid}|g" \
        "${template_dir}/sudoers.conf")

    echo "$content"
}

sudoers_install() {
    local username="$1"
    local luks_uuid="$2"
    local mapper_name="${3:-usb-secret}"
    local keyfile_path="${4:-/root/usb-luks.key}"
    local uid="${5:-$(id -u "$username" 2>/dev/null)}"

    require_root

    print_section "Sudoers drop-in"

    local content
    content=$(sudoers_generate "$username" "$luks_uuid" "$mapper_name" "$keyfile_path" "$uid")

    echo >&2
    log_info "Generated sudoers drop-in:"
    printf '%s\n' "$content" | sed 's/^/  /' >&2
    echo >&2

    if ! confirm_yn "Install to $SUDOERS_DROPIN?"; then
        log_info "Skipped sudoers installation"
        return 0
    fi

    # Write to temp and validate before installing
    local tmp
    tmp=$(mktemp)
    printf '%s\n' "$content" > "$tmp"
    chmod 440 "$tmp"

    if ! visudo -cf "$tmp"; then
        rm -f "$tmp"
        log_error "sudoers syntax validation failed — not installing"
        return 1
    fi

    mv "$tmp" "$SUDOERS_DROPIN"
    chmod 440 "$SUDOERS_DROPIN"
    chown root:root "$SUDOERS_DROPIN"

    print_ok "Installed $SUDOERS_DROPIN"
}

sudoers_validate() {
    if [[ ! -f "$SUDOERS_DROPIN" ]]; then
        print_fail "Sudoers drop-in not installed: $SUDOERS_DROPIN"
        return 1
    fi

    if visudo -cf "$SUDOERS_DROPIN" &>/dev/null; then
        print_ok "Sudoers syntax valid: $SUDOERS_DROPIN"
        return 0
    else
        print_fail "Sudoers syntax error: $SUDOERS_DROPIN"
        visudo -cf "$SUDOERS_DROPIN" >&2
        return 1
    fi
}

sudoers_check_entries() {
    local username="$1"
    print_section "sudo -l check"
    sudo -l -U "$username" 2>&1 | grep -A5 "pamusb\|cryptsetup\|luksOpen\|luksClose" | sed 's/^/  /' >&2 || true
}

sudoers_uninstall() {
    if [[ -f "$SUDOERS_DROPIN" ]]; then
        rm -f "$SUDOERS_DROPIN"
        print_ok "Removed $SUDOERS_DROPIN"
    else
        print_info "Sudoers drop-in not present"
    fi
}
