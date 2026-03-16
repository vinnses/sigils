#!/bin/bash
# lib/pam.sh — pam_usb setup, status, recovery, and test

# ─── Prerequisites ────────────────────────────────────────────────────────────

pam_check_prerequisites() {
    local ok=0

    local pam_so
    pam_so=$(find_pam_usb_so)
    if [[ -z "$pam_so" ]]; then
        log_error "pam_usb.so not found in any known PAM module directory"
        log_error "pam_usb must be built and installed before running this setup"
        print_section "Build instructions"
        local distro
        distro=$(detect_distro)
        if [[ "$distro" == "debian" ]]; then
            cat >&2 <<'EOF'
  Build dependencies (Debian/Ubuntu/Pop!_OS):
    sudo apt install build-essential libpam0g-dev libxml2-dev udisks2 \
                     python3-dbus python3-gi
  Build:
    git clone https://github.com/aluzzardi/pam_usb.git
    cd pam_usb && make && sudo make install
EOF
        elif [[ "$distro" == "arch" ]]; then
            cat >&2 <<'EOF'
  Build from AUR:
    yay -S pam_usb
  Or manually:
    git clone https://github.com/aluzzardi/pam_usb.git
    cd pam_usb && make && sudo make install
EOF
        else
            cat >&2 <<'EOF'
  Build from source: https://github.com/aluzzardi/pam_usb
  Dependencies: libpam-dev, libxml2-dev, udisks2 (dbus), python3-dbus
EOF
        fi
        ok=1
    else
        print_ok "pam_usb.so found at $pam_so"
    fi

    for cmd in pamusb-conf pamusb-check; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd not found in PATH"
            ok=1
        else
            print_ok "$cmd found"
        fi
    done

    return "$ok"
}

# ─── Device / user registration ───────────────────────────────────────────────

pam_add_device() {
    local device_name="$1"
    local username="$2"

    log_info "Registering USB device '$device_name' with pam_usb"
    log_info "(USB device must be connected)"
    echo >&2

    # pamusb-conf requires the USB device to be connected and discoverable
    if ! pamusb-conf --add-device "$device_name"; then
        log_error "pamusb-conf --add-device failed"
        return 1
    fi

    log_info "Associating user '$username' with device '$device_name'"
    if ! pamusb-conf --add-user "$username"; then
        log_error "pamusb-conf --add-user failed"
        return 1
    fi

    print_ok "Device '$device_name' registered for user '$username'"
    return 0
}

# ─── PAM file configuration ───────────────────────────────────────────────────

# Prepend pam_usb auth line to a PAM file
pam_configure_file() {
    local pam_file="$1"
    local pam_line="auth    sufficient    pam_usb.so"

    if [[ ! -f "$pam_file" ]]; then
        log_warn "$pam_file does not exist — skipping"
        return 0
    fi

    # Check if already configured
    if grep -qF "pam_usb.so" "$pam_file"; then
        print_ok "$pam_file already contains pam_usb.so — skipping"
        return 0
    fi

    print_section "Configure PAM: $(basename "$pam_file")"

    echo >&2
    log_info "Current contents of $pam_file:"
    cat "$pam_file" | sed 's/^/  /' >&2
    echo >&2

    log_info "Proposed change: add at top of auth section:"
    printf "  ${C_BGREEN}+ %s${C_RESET}\n" "$pam_line" >&2
    echo >&2

    if ! confirm_yn "Apply this change to $pam_file?"; then
        log_info "Skipped $pam_file"
        return 0
    fi

    # Create backup
    cp "$pam_file" "${pam_file}.usb-auth.bak"
    log_info "Backup saved to ${pam_file}.usb-auth.bak"

    # Insert line at top (before any existing auth lines)
    local tmp
    tmp=$(mktemp)
    local inserted=false

    while IFS= read -r line; do
        if [[ "$inserted" == "false" && "$line" =~ ^auth ]]; then
            printf '%s\n' "$pam_line" >> "$tmp"
            inserted=true
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$pam_file"

    # If no auth line found, prepend to file
    if [[ "$inserted" == "false" ]]; then
        { printf '%s\n' "$pam_line"; cat "$pam_file"; } > "$tmp"
    fi

    mv "$tmp" "$pam_file"
    print_ok "Updated $pam_file"
    return 0
}

pam_configure_all() {
    local target_files=(
        "/etc/pam.d/sudo"
        "/etc/pam.d/polkit-1"
    )

    # Add display manager files
    while IFS= read -r dm_file; do
        target_files+=("$dm_file")
    done < <(detect_display_manager_pam)

    for pam_file in "${target_files[@]}"; do
        pam_configure_file "$pam_file"
    done
}

# Revert all pam_usb changes (remove the auth line, restore from backup if available)
pam_revert_files() {
    local target_files=(
        "/etc/pam.d/sudo"
        "/etc/pam.d/polkit-1"
    )
    while IFS= read -r dm_file; do
        target_files+=("$dm_file")
    done < <(detect_display_manager_pam)

    for pam_file in "${target_files[@]}"; do
        [[ ! -f "$pam_file" ]] && continue

        if [[ -f "${pam_file}.usb-auth.bak" ]]; then
            mv "${pam_file}.usb-auth.bak" "$pam_file"
            print_ok "Restored $pam_file from backup"
        else
            # Remove pam_usb line manually
            sed -i '/pam_usb\.so/d' "$pam_file"
            print_ok "Removed pam_usb.so line from $pam_file"
        fi
    done
}

# ─── Lock/unlock system ───────────────────────────────────────────────────────

pam_install_guard() {
    local username="$1"
    local main_uuid="$2"
    local template_dir="${SPELL_DIR}/templates"
    local dest="/usr/local/bin/usb-pam-guard.sh"

    log_info "Installing debounce guard script to $dest"

    local content
    content=$(sed \
        -e "s|{{USERNAME}}|${username}|g" \
        -e "s|{{MAIN_UUID}}|${main_uuid}|g" \
        "${template_dir}/guard.sh")

    printf '%s\n' "$content" > "$dest"
    chmod 755 "$dest"
    print_ok "Installed $dest"
}

pam_install_dispatch() {
    local username="$1"
    local template_dir="${SPELL_DIR}/templates"
    local dest="/usr/local/bin/usb-pam-dispatch.sh"

    log_info "Installing dispatch script to $dest"

    local content
    content=$(sed \
        -e "s|{{USERNAME}}|${username}|g" \
        "${template_dir}/dispatch.sh")

    printf '%s\n' "$content" > "$dest"
    chmod 755 "$dest"
    print_ok "Installed $dest"
}

pam_install_udev_lock_rule() {
    local main_uuid="$1"
    local template_dir="${SPELL_DIR}/templates"
    local dest="/etc/udev/rules.d/90-usb-lock.rules"

    log_info "Installing udev lock rule to $dest"

    local content
    content=$(sed \
        -e "s|{{MAIN_UUID}}|${main_uuid}|g" \
        "${template_dir}/udev-lock.rules")

    printf '%s\n' "$content" > "$dest"
    udevadm control --reload-rules
    udevadm trigger
    print_ok "Installed $dest and reloaded udev"
}

pam_remove_lock_system() {
    local files=(
        "/usr/local/bin/usb-pam-guard.sh"
        "/usr/local/bin/usb-pam-dispatch.sh"
        "/etc/udev/rules.d/90-usb-lock.rules"
    )
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            print_ok "Removed $f"
        fi
    done
    udevadm control --reload-rules 2>/dev/null
}

# ─── Status ───────────────────────────────────────────────────────────────────

pam_status() {
    local device_name
    device_name=$(conf_get "PAM_DEVICE_NAME")
    local pam_user
    pam_user=$(conf_get "PAM_USER")

    print_section "pam_usb status"

    # pam_usb.so
    local pam_so
    pam_so=$(find_pam_usb_so)
    if [[ -n "$pam_so" ]]; then
        print_ok "pam_usb.so: $pam_so"
    else
        print_fail "pam_usb.so: not found"
    fi

    # pamusb-conf / pamusb-check
    for cmd in pamusb-conf pamusb-check; do
        if command -v "$cmd" &>/dev/null; then
            print_ok "$cmd: $(command -v "$cmd")"
        else
            print_fail "$cmd: not in PATH"
        fi
    done

    # Device registered
    if [[ -n "$device_name" ]] && grep -q "name=\"${device_name}\"" /etc/security/pam_usb.conf 2>/dev/null; then
        print_ok "Device registered: $device_name"
    else
        print_fail "Device not registered in pam_usb.conf (name: ${device_name:-unset})"
    fi

    # User associated
    if [[ -n "$pam_user" ]] && grep -q "name=\"${pam_user}\"" /etc/security/pam_usb.conf 2>/dev/null; then
        print_ok "User associated: $pam_user"
    else
        print_fail "User not associated in pam_usb.conf (user: ${pam_user:-unset})"
    fi

    # PAM files
    for pam_file in /etc/pam.d/sudo /etc/pam.d/polkit-1 $(detect_display_manager_pam); do
        [[ ! -f "$pam_file" ]] && continue
        if grep -q "pam_usb.so" "$pam_file" 2>/dev/null; then
            print_ok "PAM configured: $pam_file"
        else
            print_fail "PAM not configured: $pam_file"
        fi
    done

    # Udev rule
    if [[ -f /etc/udev/rules.d/90-usb-lock.rules ]]; then
        print_ok "udev lock rule: /etc/udev/rules.d/90-usb-lock.rules"
    else
        print_fail "udev lock rule: not installed"
    fi

    # Guard/dispatch scripts
    for script in /usr/local/bin/usb-pam-guard.sh /usr/local/bin/usb-pam-dispatch.sh; do
        if [[ -x "$script" ]]; then
            print_ok "Script installed: $script"
        else
            print_fail "Script missing: $script"
        fi
    done
}

# ─── Test ─────────────────────────────────────────────────────────────────────

pam_test() {
    local username="${1:-$USER}"

    print_section "pam_usb diagnostic"

    if ! command -v pamusb-check &>/dev/null; then
        log_error "pamusb-check not found"
        return 1
    fi

    echo >&2
    log_info "Running: pamusb-check $username"
    echo >&2

    if pamusb-check "$username"; then
        print_ok "pamusb-check passed for $username"
        return 0
    else
        print_fail "pamusb-check failed for $username"
        return 1
    fi
}

# ─── Recovery ─────────────────────────────────────────────────────────────────

pam_recover_pads() {
    local username="${1:-$USER}"

    print_section "pam_usb pad recovery"
    log_warn "This resets the OTP pad synchronization between the USB device and pam_usb config."
    log_warn "Both the USB and the host must be accessible."
    echo >&2

    if ! confirm_yes "Type 'yes' to reset OTP pads for $username"; then
        log_info "Aborted pad recovery"
        return 1
    fi

    log_info "Resetting pads for $username"
    if ! pamusb-conf --reset-pads="$username"; then
        log_error "pamusb-conf --reset-pads failed"
        return 1
    fi

    print_ok "Pads reset successfully"
    log_info "Verifying with pamusb-check"
    pam_test "$username"
}

# ─── Uninstall ────────────────────────────────────────────────────────────────

pam_uninstall() {
    local device_name
    device_name=$(conf_get "PAM_DEVICE_NAME")
    local pam_user
    pam_user=$(conf_get "PAM_USER")

    print_section "Uninstalling pam_usb configuration"

    # Revert PAM files
    pam_revert_files

    # Remove lock/unlock scripts
    pam_remove_lock_system

    # Remove device and user from pam_usb.conf
    if [[ -n "$device_name" ]] && confirm_yn "Remove device '$device_name' from pam_usb.conf?"; then
        pamusb-conf --remove-device "$device_name" 2>/dev/null || true
        print_ok "Device removed from pam_usb.conf"
    fi

    if [[ -n "$pam_user" ]] && confirm_yn "Remove user '$pam_user' from pam_usb.conf?"; then
        pamusb-conf --remove-user "$pam_user" 2>/dev/null || true
        print_ok "User removed from pam_usb.conf"
    fi
}
