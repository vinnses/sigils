#!/bin/bash
# lib/keyring.sh — GNOME Keyring LUKS setup, unlock, rekey, and status

# ─── Constants ────────────────────────────────────────────────────────────────

: "${LUKS_KEYFILE:="/root/usb-luks.key"}"
: "${LUKS_MAPPER_NAME:="usb-secret"}"
: "${LUKS_MOUNT_BASE:="/run/user"}"

_luks_mountpoint() {
    local uid="${1:-$(id -u)}"
    echo "${LUKS_MOUNT_BASE}/${uid}/usb-secret"
}

# ─── Keyfile management ───────────────────────────────────────────────────────

keyring_setup_keyfile() {
    require_root

    if [[ -f "$LUKS_KEYFILE" ]]; then
        log_info "LUKS keyfile already exists at $LUKS_KEYFILE"
        print_section "Existing keyfile detected"
        printf "  ${C_BOLD}a)${C_RESET} Reuse existing keyfile (multi-machine scenario — keyfile was copied from another host)\n" >&2
        printf "  ${C_BOLD}b)${C_RESET} Generate new keyfile (overwrites — only if this is a fresh single-machine setup)\n" >&2

        local choice
        while true; do
            printf "${C_BOLD}Choose [a/b]:${C_RESET} " >&2
            read -r choice
            case "${choice,,}" in
                a) log_info "Reusing existing keyfile"; return 0 ;;
                b)
                    log_warn "This will overwrite $LUKS_KEYFILE and invalidate any existing LUKS container keyed to it"
                    if confirm_yes "Type 'yes' to overwrite LUKS keyfile"; then
                        break
                    fi
                    log_info "Aborted keyfile regeneration"
                    return 0
                    ;;
                *) printf "Please choose a or b.\n" >&2 ;;
            esac
        done
    fi

    log_info "Generating new LUKS keyfile at $LUKS_KEYFILE"
    dd if=/dev/urandom of="$LUKS_KEYFILE" bs=512 count=8 status=none || {
        log_error "Failed to generate keyfile"
        return 1
    }
    chmod 400 "$LUKS_KEYFILE"
    print_ok "Keyfile generated: $LUKS_KEYFILE (chmod 400)"
}

# ─── LUKS container setup ─────────────────────────────────────────────────────

keyring_luks_format() {
    local partition="$1"
    require_root

    log_warn "This will DESTROY all data on $partition"
    log_warn "Keyfile: $LUKS_KEYFILE"
    if ! confirm_yes "Type 'yes' to format $partition as LUKS2"; then
        log_info "LUKS format aborted"
        return 1
    fi

    log_info "Formatting $partition as LUKS2"
    cryptsetup luksFormat --type luks2 -q "$partition" "$LUKS_KEYFILE" || {
        log_error "cryptsetup luksFormat failed on $partition"
        return 1
    }
    print_ok "LUKS2 formatted: $partition"

    log_info "Opening LUKS container as $LUKS_MAPPER_NAME"
    cryptsetup luksOpen "$partition" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE" || {
        log_error "cryptsetup luksOpen failed"
        return 1
    }

    log_info "Creating ext4 filesystem inside LUKS"
    mkfs.ext4 -q "/dev/mapper/${LUKS_MAPPER_NAME}" || {
        cryptsetup luksClose "$LUKS_MAPPER_NAME"
        log_error "mkfs.ext4 failed"
        return 1
    }

    cryptsetup luksClose "$LUKS_MAPPER_NAME"
    print_ok "LUKS container formatted and closed"
}

# ─── Open/close helpers ───────────────────────────────────────────────────────

keyring_luks_open() {
    local partition="$1"
    require_root

    if [[ -e "/dev/mapper/${LUKS_MAPPER_NAME}" ]]; then
        log_info "LUKS mapper $LUKS_MAPPER_NAME already open"
        return 0
    fi

    cryptsetup luksOpen "$partition" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE" || {
        log_error "Failed to open LUKS container on $partition"
        return 1
    }
    log_debug "LUKS container opened: /dev/mapper/${LUKS_MAPPER_NAME}"
}

keyring_luks_close() {
    require_root
    if [[ ! -e "/dev/mapper/${LUKS_MAPPER_NAME}" ]]; then
        return 0
    fi
    cryptsetup luksClose "$LUKS_MAPPER_NAME" || {
        log_error "Failed to close LUKS container $LUKS_MAPPER_NAME"
        return 1
    }
    log_debug "LUKS container closed"
}

keyring_mount() {
    local uid="${1:-$(id -u)}"
    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")
    require_root

    if usb_is_mounted "/dev/mapper/${LUKS_MAPPER_NAME}"; then
        log_debug "Already mounted at $mountpoint"
        return 0
    fi

    mkdir -p "$mountpoint"
    mount "/dev/mapper/${LUKS_MAPPER_NAME}" "$mountpoint" || {
        log_error "Failed to mount LUKS container at $mountpoint"
        return 1
    }
    log_debug "LUKS mounted at $mountpoint"
}

keyring_umount() {
    local uid="${1:-$(id -u)}"
    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")
    require_root

    if ! usb_is_mounted "/dev/mapper/${LUKS_MAPPER_NAME}"; then
        return 0
    fi

    umount "$mountpoint" || {
        log_error "Failed to unmount $mountpoint"
        return 1
    }
    log_debug "LUKS unmounted"
}

# ─── Provisioning ─────────────────────────────────────────────────────────────

keyring_provision() {
    local partition="$1"
    local hostname_target="${2:-$(hostname)}"
    local uid
    uid=$(id -u)

    require_root

    keyring_luks_open "$partition" || return 1
    keyring_mount "$uid" || { keyring_luks_close; return 1; }

    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")

    mkdir -p "${mountpoint}/keyring-pass"

    local password
    prompt_secret_confirm "GNOME Keyring login password for $hostname_target" password

    printf '%s' "$password" > "${mountpoint}/keyring-pass/${hostname_target}"
    chmod 400 "${mountpoint}/keyring-pass/${hostname_target}"

    log_info "Keyring payload written for hostname: $hostname_target"
    print_ok "Payload stored at keyring-pass/${hostname_target}"

    keyring_umount "$uid"
    keyring_luks_close
}

# ─── Unlock script (runtime, non-root) ───────────────────────────────────────

# Called at session start via XDG autostart
keyring_unlock_runtime() {
    local luks_uuid
    luks_uuid=$(conf_get "USB_LUKS_PARTITION_UUID")
    local uid
    uid=$(id -u)
    local log_file="${XDG_RUNTIME_DIR:-/tmp}/usb-auth-keyring.log"
    local hostname_target
    hostname_target=$(hostname)

    exec >> "$log_file" 2>&1
    printf '%s [INFO] usb-auth keyring unlock started\n' "$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ -z "$luks_uuid" ]]; then
        printf '%s [ERROR] USB_LUKS_PARTITION_UUID not configured\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    fi

    local luks_dev
    printf '%s [INFO] Waiting for LUKS UUID %s...\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$luks_uuid"
    luks_dev=$(usb_wait_for_uuid "$luks_uuid" 30) || {
        printf '%s [ERROR] LUKS device not found (timeout)\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    }

    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")

    # Open LUKS via sudoers-authorized cryptsetup
    printf '%s [INFO] Opening LUKS container\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    sudo cryptsetup luksOpen "$luks_dev" "$LUKS_MAPPER_NAME" --key-file "$LUKS_KEYFILE" || {
        printf '%s [ERROR] cryptsetup luksOpen failed\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        exit 1
    }

    mkdir -p "$mountpoint"
    sudo mount "/dev/mapper/${LUKS_MAPPER_NAME}" "$mountpoint" || {
        printf '%s [ERROR] mount failed\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        sudo cryptsetup luksClose "$LUKS_MAPPER_NAME"
        exit 1
    }

    local payload_file="${mountpoint}/keyring-pass/${hostname_target}"
    if [[ ! -f "$payload_file" ]]; then
        printf '%s [ERROR] No payload for hostname %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$hostname_target"
        sudo umount "$mountpoint"
        sudo cryptsetup luksClose "$LUKS_MAPPER_NAME"
        exit 1
    fi

    printf '%s [INFO] Unlocking GNOME Keyring\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    cat "$payload_file" | gnome-keyring-daemon --unlock || {
        printf '%s [WARN] gnome-keyring-daemon --unlock returned non-zero\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    }

    sudo umount "$mountpoint"
    sudo cryptsetup luksClose "$LUKS_MAPPER_NAME"

    printf '%s [INFO] Keyring unlock complete\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

# Install standalone unlock wrapper to ~/.local/bin/
keyring_install_unlock_script() {
    local target_dir="${HOME}/.local/bin"
    local script="${target_dir}/usb-auth-unlock-keyring.sh"
    local spell_dir="${SPELL_DIR}"
    local conf_file="${CONF_FILE}"

    mkdir -p "$target_dir"

    cat > "$script" <<EOF
#!/bin/bash
# usb-auth keyring unlock wrapper — generated by usb-auth setup
# DO NOT EDIT — regenerate with: usb-auth setup-keyring

SPELL_DIR="${spell_dir}"
CONF_FILE="${conf_file}"

source "\${CONF_FILE}" 2>/dev/null
source "\${SPELL_DIR}/lib/common.sh"
source "\${SPELL_DIR}/lib/keyring.sh"

keyring_unlock_runtime
EOF

    chmod 755 "$script"
    print_ok "Installed unlock script: $script"
}

# ─── Rekey ────────────────────────────────────────────────────────────────────

keyring_rekey() {
    local partition="$1"
    local hostname_target="${2:-$(hostname)}"
    local uid
    uid=$(id -u)

    require_root

    print_section "Keyring rekey for $hostname_target"

    keyring_luks_open "$partition" || return 1
    keyring_mount "$uid" || { keyring_luks_close; return 1; }

    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")
    local payload_file="${mountpoint}/keyring-pass/${hostname_target}"

    if [[ ! -f "$payload_file" ]]; then
        keyring_umount "$uid"
        keyring_luks_close
        log_error "No payload found for hostname '$hostname_target'. Use provision-host to create one."
        return 1
    fi

    local new_password
    prompt_secret_confirm "New GNOME Keyring password for $hostname_target" new_password

    printf '%s' "$new_password" > "$payload_file"
    chmod 400 "$payload_file"

    keyring_umount "$uid"
    keyring_luks_close

    print_ok "Keyring password updated for $hostname_target"
}

# ─── Provision host ───────────────────────────────────────────────────────────

keyring_provision_host() {
    local partition="$1"
    local uid
    uid=$(id -u)

    require_root

    local hostname_target
    prompt_value "Hostname to provision" hostname_target "$(hostname)"

    print_section "Provisioning host: $hostname_target"

    keyring_luks_open "$partition" || return 1
    keyring_mount "$uid" || { keyring_luks_close; return 1; }

    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")

    mkdir -p "${mountpoint}/keyring-pass"

    if [[ -f "${mountpoint}/keyring-pass/${hostname_target}" ]]; then
        log_warn "Payload already exists for $hostname_target"
        if ! confirm_yn "Overwrite?"; then
            keyring_umount "$uid"
            keyring_luks_close
            return 0
        fi
    fi

    local password
    prompt_secret_confirm "GNOME Keyring password for $hostname_target" password
    printf '%s' "$password" > "${mountpoint}/keyring-pass/${hostname_target}"
    chmod 400 "${mountpoint}/keyring-pass/${hostname_target}"

    print_section "Provisioned hosts"
    ls -1 "${mountpoint}/keyring-pass/" >&2

    keyring_umount "$uid"
    keyring_luks_close
    print_ok "Host $hostname_target provisioned"
}

# ─── Status ───────────────────────────────────────────────────────────────────

keyring_status() {
    local luks_uuid
    luks_uuid=$(conf_get "USB_LUKS_PARTITION_UUID")

    print_section "Keyring status"

    # Keyfile
    if [[ -f "$LUKS_KEYFILE" ]]; then
        local perms
        perms=$(stat -c '%a' "$LUKS_KEYFILE" 2>/dev/null)
        print_ok "LUKS keyfile: $LUKS_KEYFILE (mode $perms)"
    else
        print_fail "LUKS keyfile not found: $LUKS_KEYFILE"
    fi

    # Sudoers
    if [[ -f /etc/sudoers.d/99-usb-auth ]]; then
        print_ok "Sudoers drop-in: /etc/sudoers.d/99-usb-auth"
    else
        print_fail "Sudoers drop-in: not installed"
    fi

    # Autostart
    local autostart="${HOME}/.config/autostart/usb-auth-keyring.desktop"
    if [[ -f "$autostart" ]]; then
        print_ok "Autostart: $autostart"
    else
        print_fail "Autostart: not installed"
    fi

    # Unlock script
    local unlock_script="${HOME}/.local/bin/usb-auth-unlock-keyring.sh"
    if [[ -x "$unlock_script" ]]; then
        print_ok "Unlock script: $unlock_script"
    else
        print_fail "Unlock script: not installed"
    fi

    # udev suppress rule
    if [[ -f /etc/udev/rules.d/91-usb-auth-suppress.rules ]]; then
        print_ok "udev suppress rule: /etc/udev/rules.d/91-usb-auth-suppress.rules"
    else
        print_fail "udev suppress rule: not installed"
    fi

    # Payload for this hostname
    if [[ -n "$luks_uuid" ]]; then
        local luks_dev="/dev/disk/by-uuid/${luks_uuid}"
        if [[ -e "$luks_dev" ]]; then
            print_ok "LUKS device found: $luks_dev"
        else
            print_warn "LUKS device not present (UUID: $luks_uuid)"
        fi
    else
        print_warn "USB_LUKS_PARTITION_UUID not configured"
    fi
}

# ─── Test ─────────────────────────────────────────────────────────────────────

keyring_test() {
    local partition="$1"
    local uid
    uid=$(id -u)
    local hostname_target
    hostname_target=$(hostname)

    require_root

    print_section "Keyring LUKS cycle test (dry-run)"

    log_info "Opening LUKS container"
    keyring_luks_open "$partition" || return 1

    log_info "Mounting LUKS container"
    keyring_mount "$uid" || { keyring_luks_close; return 1; }

    local mountpoint
    mountpoint=$(_luks_mountpoint "$uid")

    local payload_file="${mountpoint}/keyring-pass/${hostname_target}"
    if [[ -f "$payload_file" ]]; then
        print_ok "Payload exists: $payload_file"
        local size
        size=$(wc -c < "$payload_file")
        print_info "Payload size: $size bytes"
    else
        print_fail "Payload not found for hostname '$hostname_target'"
        print_info "Available hostnames:"
        ls -1 "${mountpoint}/keyring-pass/" 2>/dev/null | sed 's/^/    /' >&2
    fi

    log_info "Unmounting and closing LUKS container"
    keyring_umount "$uid"
    keyring_luks_close

    print_ok "LUKS cycle test complete (no keyring injection)"
}

# ─── Uninstall ────────────────────────────────────────────────────────────────

keyring_uninstall() {
    local luks_uuid
    luks_uuid=$(conf_get "USB_LUKS_PARTITION_UUID")

    print_section "Uninstalling keyring configuration"

    # Autostart
    local autostart="${HOME}/.config/autostart/usb-auth-keyring.desktop"
    if [[ -f "$autostart" ]] && confirm_yn "Remove autostart entry $autostart?"; then
        rm -f "$autostart"
        print_ok "Removed $autostart"
    fi

    # Unlock script
    local unlock_script="${HOME}/.local/bin/usb-auth-unlock-keyring.sh"
    if [[ -f "$unlock_script" ]] && confirm_yn "Remove unlock script $unlock_script?"; then
        rm -f "$unlock_script"
        print_ok "Removed $unlock_script"
    fi

    # Sudoers (handled by sudoers.sh uninstall)

    # udev suppress rule
    if [[ -f /etc/udev/rules.d/91-usb-auth-suppress.rules ]]; then
        rm -f /etc/udev/rules.d/91-usb-auth-suppress.rules
        udevadm control --reload-rules 2>/dev/null
        print_ok "Removed udev suppress rule"
    fi

    # LUKS keyfile (optional)
    if [[ -f "$LUKS_KEYFILE" ]] && confirm_yn "Remove LUKS keyfile $LUKS_KEYFILE? (cannot be recovered)"; then
        shred -u "$LUKS_KEYFILE" 2>/dev/null || rm -f "$LUKS_KEYFILE"
        print_ok "Removed $LUKS_KEYFILE"
    fi

    # Wipe LUKS partition (optional)
    if [[ -n "$luks_uuid" ]]; then
        local luks_dev="/dev/disk/by-uuid/${luks_uuid}"
        if [[ -e "$luks_dev" ]] && confirm_yn "Wipe LUKS partition $luks_dev? (DESTROYS all keyring payloads)"; then
            log_warn "Wiping LUKS partition header on $luks_dev"
            cryptsetup erase "$luks_dev" 2>/dev/null || dd if=/dev/urandom of="$luks_dev" bs=1M count=4 status=none
            print_ok "LUKS partition wiped"
        fi
    fi
}
